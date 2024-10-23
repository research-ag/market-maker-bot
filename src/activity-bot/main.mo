import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Timer "mo:base/Timer";

import PT "mo:promtracker";
import Vec "mo:vector";

import Auction "../market-maker-bot-backend/auction_definitions";
import AuctionWrapper "../market-maker-bot-backend/auction_wrapper";
import HTTP "../market-maker-bot-backend/http";
import MarketMaker "../market-maker-bot-backend/market_maker";
import OracleWrapper "../market-maker-bot-backend/oracle_wrapper";
import Tokens "../market-maker-bot-backend/tokens";
import U "../market-maker-bot-backend/utils";

import HistoryModule "./history";

actor class ActivityBot(auction_be_ : ?Principal, oracle_be_ : ?Principal) = self {

  stable let auction_principal : Principal = switch (auction_be_) {
    case (?p) p;
    case (_) Prim.trap("Auction principal not provided");
  };
  stable let oracle_principal : Principal = switch (oracle_be_) {
    case (?p) p;
    case (_) Prim.trap("Oracle principal not provided");
  };

  stable var marketPairs : AssocList.AssocList<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair> = null;
  stable let history : Vec.Vector<HistoryModule.HistoryItemType> = Vec.new();

  let tokens_info : AssocList.AssocList<Principal, Tokens.TokenInfo> = Tokens.getTokensInfo();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread_value : Float = 0.1;

  var bot_timer : Timer.TimerId = 0;

  /// Bot state flags and variables
  stable var bot_timer_interval : Nat = 6 * 60;
  stable var is_running : Bool = false;
  var is_initialized : Bool = false;
  var is_initializing : Bool = false;
  var quote : ?MarketMaker.TokenDescription = null;
  var supported_tokens : [Principal] = [];
  /// End Bot state flags and variables

  let metrics = PT.PromTracker("", 65);
  metrics.addSystemValues();
  ignore metrics.addPullValue("bot_timer_interval", "", func() = bot_timer_interval);
  ignore metrics.addPullValue("running", "", func() = if (is_running) { 1 } else { 0 });

  func getState() : (BotState) {
    {
      timer_interval = bot_timer_interval;
      running = is_running;
      initialized = is_initialized;
      initializing = is_initializing;
      quote_token = switch (quote) {
        case (?q) { ?q.principal };
        case (null) { null };
      };
      supported_tokens = supported_tokens;
    };
  };

  public func init() : async {
    #Ok : (BotState);
    #Err : ({
      #UnknownQuoteTokenError;
      #InitializingInProgressError;
      #AlreadyInitializedError;
      #UnknownError;
    });
  } {
    if (is_initializing) return #Err(#InitializingInProgressError);
    if (is_initialized) return #Err(#AlreadyInitializedError);

    try {
      is_initializing := true;
      Debug.print("Init bot: " # Principal.toText(auction_principal) # " " # Principal.toText(oracle_principal));
      let qp = await* auction.getQuoteToken();
      supported_tokens := await* auction.getSupportedTokens();
      let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, qp, Principal.equal, "Error get quote token info");
      quote := ?{
        principal = qp;
        symbol = quote_token_info.symbol;
        decimals = quote_token_info.decimals;
      };

      for (token in supported_tokens.vals()) {
        if (not Principal.equal(token, qp)) {
          switch (AssocList.find(tokens_info, token, Principal.equal)) {
            case (?_) {
              let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, token, Principal.equal, "Error get base token info");
              let pair = {
                base = {
                  principal = token;
                  symbol = base_token_info.symbol;
                  decimals = base_token_info.decimals;
                };
                var base_credits = 0;
                var quote_credits = 0;
                var locked_quote_credits = 0;
                var spread_value = default_spread_value;
              };

              let (upd, oldValue) = AssocList.replace<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair>(
                marketPairs,
                (quote_token_info.symbol, pair.base.symbol),
                func((x1, y1), (x2, y2)) = Text.equal(x1, x2) and Text.equal(y1, y2),
                ?pair,
              );
              switch (oldValue) {
                case (?_) {};
                case (null) marketPairs := upd;
              };
            };
            case (_) {};
          };
        };
      };
      for ((_, pair) in List.toIter(marketPairs)) {
        let labels = "base=\"" # pair.base.symbol # "\"";

        ignore metrics.addPullValue("base_credits", labels, func() = pair.base_credits);
        ignore metrics.addPullValue("quote_credits", labels, func() = pair.quote_credits);
        ignore metrics.addPullValue("spread_percent", labels, func() = Int.abs(Float.toInt(0.5 + pair.spread_value * 100)));
      };
      is_initialized := true;
      is_initializing := false;
      return #Ok(getState());
    } catch (_) {
      is_initializing := false;
      return #Err(#UnknownError);
    };
  };

  public type BotState = {
    timer_interval : Nat;
    running : Bool;
    initialized : Bool;
    initializing : Bool;
    quote_token : ?Principal;
    supported_tokens : [Principal];
  };

  public query func http_request(req : HTTP.HttpRequest) : async HTTP.HttpResponse {
    let ?path = Text.split(req.url, #char '?').next() else return HTTP.render400();
    switch (req.method, path, is_initialized) {
      case ("GET", "/metrics", true) metrics.renderExposition("canister=\"" # PT.shortName(self) # "\"") |> HTTP.renderPlainText(_);
      case (_) HTTP.render400();
    };
  };

  system func preupgrade() {
    Debug.print("Preupgrade");
  };

  system func postupgrade() {
    Debug.print("Postupgrade");
    ignore Timer.setTimer<system>(
      #seconds(0),
      func() : async () {
        Debug.print("Init fired");
        ignore await init();
        if (is_running) {
          runTimer<system>();
        };
      },
    );
  };

  func addHistoryItem(pair : MarketMaker.MarketPair, bidOrder : ?MarketMaker.OrderInfo, rate : ?Float, message : Text) : () {
    let historyItem = HistoryModule.new(pair, bidOrder, rate, message);
    Vec.add(history, historyItem);
    Debug.print(HistoryModule.getText(historyItem));
  };

  func cancelAllOrders() : async* {
    #Ok : ();
    #Err : ();
  } {
    let pairs = List.toArray(marketPairs);

    if (pairs.size() == 0) {
      return #Ok;
    };

    let tokens = Array.tabulate<Principal>(
      pairs.size(),
      func(i : Nat) : Principal = pairs[i].1.base.principal,
    );

    let execute_result = await* auction.removeOrders(tokens);

    switch (execute_result) {
      case (#Ok) {
        addHistoryItem(pairs[0].1, null, null, "BIDS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(pairs[0].1, null, null, "BIDS REMOVING ERROR: " # U.getErrorMessage(err));
        return #Err;
      };
    };
  };
  func getQuoteCredit() : async* Nat {
    let quote_token = U.requireMsg(quote, "Not initialized").principal;
    ignore await* auction.notify(quote_token);
    let credit = await* auction.getCredit(quote_token);
    Int.abs(Int.max(0, credit));
  };

  /// to make it faster let's not ask about credits here, just return paris list
  /// we will manage credits and funds limit in separate place, so here is we can just return existing data
  public query func getPairsList() : async ([MarketMaker.MarketPairShared]) {
    let pairs = List.toArray(marketPairs);
    // let token_credits = await* getCredits();
    Array.tabulate<MarketMaker.MarketPairShared>(
      pairs.size(),
      func(i : Nat) : MarketMaker.MarketPairShared = MarketMaker.sharePair(pairs[i].1),
    );
  };

  public query func getHistory(limit : Nat, skip : Nat) : async ([HistoryModule.HistoryItemType]) {
    let size : Int = Vec.size(history) - skip;
    if (size < 1) return [];
    Array.tabulate<HistoryModule.HistoryItemType>(
      Nat.min(Int.abs(size), limit),
      func(i : Nat) : HistoryModule.HistoryItemType = Vec.get(history, i + skip),
    );
  };

  public query func getBotState() : async (BotState) {
    getState();
  };

  public func startBot(timer_interval : Nat) : async {
    #Ok : (BotState);
    #Err : ({
      #NotInitializedError;
      #AlreadyStartedError;
    });
  } {
    Debug.print("Start bot");

    if (is_initialized == false) {
      return #Err(#NotInitializedError);
    };

    if (is_running == true) {
      return #Err(#AlreadyStartedError);
    };

    is_running := true;

    bot_timer_interval := timer_interval;
    runTimer<system>();

    ignore Timer.setTimer<system>(
      #seconds(0),
      func() : async () {
        await executeBot();
      },
    );

    #Ok(getState());
  };

  public func stopBot() : async {
    #Ok : (BotState);
    #Err : ({
      #NotInitializedError;
      #AlreadyStopedError;
      #CancelOrdersError;
    });
  } {
    Debug.print("Stop bot");

    if (is_initialized == false) {
      return #Err(#NotInitializedError);
    };

    if (is_running == false) {
      return #Err(#AlreadyStopedError);
    };

    try {
      let remove_orders_result = await* cancelAllOrders();
      switch (remove_orders_result) {
        case (#Ok) {
          is_running := false;
          stopTimer();
          return #Ok(getState());
        };
        case (#Err) {
          return #Err(#CancelOrdersError);
        };
      };
    } catch (_) {
      return #Err(#CancelOrdersError);
    };
  };

  public func migrate_auction_credits(source_auction : Principal, dest_auction : Principal) : async Text {
    assert not is_running;
    let src : Auction.Self = actor (Principal.toText(source_auction));

    func toSubaccount(p : Principal) : Blob {
      let bytes = Blob.toArray(Principal.toBlob(p));
      let size = bytes.size();
      assert size <= 29;
      Array.tabulate<Nat8>(
        32,
        func(i : Nat) : Nat8 {
          if (i + size < 31) {
            0;
          } else if (i + size == 31) {
            Nat8.fromNat(size);
          } else {
            bytes[i + size - 32];
          };
        },
      ) |> Blob.fromArray(_);
    };
    let destSubaccount = toSubaccount(Principal.fromActor(self));

    ignore await src.manageOrders(? #all(null), [], null);
    let credits = await src.queryCredits();
    for ((_, acc, _) in credits.vals()) {
      assert acc.locked == 0;
    };
    for ((token, acc, _) in credits.vals()) {
      ignore await src.icrc84_withdraw({
        to = { owner = dest_auction; subaccount = ?destSubaccount };
        amount = acc.available;
        token;
        expected_fee = null;
      });
    };
    "Credits transferred to subaccount: " # debug_show destSubaccount # "; src credits: " # debug_show (await src.queryCredits()) # "; dest credits: " # debug_show (await src.queryCredits());
  };

  public func executeActivityBot() : async () {
    let quote_credits = await* getQuoteCredit();
    let quote_token = U.requireMsg(quote, "Not initialized");

    for ((_, pair) in List.toIter(marketPairs)) {

      pair.quote_credits := quote_credits;

      if (quote_credits == 0) {
        addHistoryItem(pair, null, null, "Error processing pair: empty credits for " # Principal.toText(quote_token.principal));
      } else {
        let current_rate_result = await* oracle.getExchangeRate(pair.base.symbol, quote_token.symbol);
        // calculate multiplicator which help to normalize the price before create
        // the order to the smallest units of the tokens
        let price_decimals_multiplicator : Int32 = Int32.fromNat32(quote_token.decimals) - Int32.fromNat32(pair.base.decimals);

        switch (current_rate_result) {
          case (#Ok(current_rate)) {
            // get ask price, because in activity bot we want to place higher bid values
            let { ask_price = price } = MarketMaker.getPrices(pair.spread_value, current_rate, price_decimals_multiplicator);
            // bid minimum volume
            func getBaseVolumeStep(price : Float) : Nat {
              let p = price / Float.fromInt(1000);
              if (p >= 1) return 1;
              let zf = - Float.log(p) / 2.302_585_092_994_045;
              Int.abs(10 ** Float.toInt(zf));
            };
            let volumeStep = getBaseVolumeStep(price);
            var amount = (5000.0 / price) |> Float.ceil(_) |> Float.toInt(_) |> Int.abs(_);
            if (amount % volumeStep > 0) {
              amount += volumeStep - (amount % volumeStep);
            };

            let bid_order : MarketMaker.OrderInfo = { amount; price };

            let replace_orders_result = await* auction.replaceOrders(pair.base.principal, bid_order, { amount = 0; price = 0 }, null);

            let res = switch (replace_orders_result) {
              case (#Ok(_)) #Ok(bid_order, current_rate);
              case (#Err(err)) {
                switch (err) {
                  case (#placement(err)) {
                    switch (err.error) {
                      case (#ConflictingOrder(_)) #Err(#ConflictOrderError, ?bid_order, ?current_rate);
                      case (#UnknownAsset) #Err(#UnknownAssetError, ?bid_order, ?current_rate);
                      case (#NoCredit) #Err(#NoCreditError, ?bid_order, ?current_rate);
                      case (#TooLowOrder) #Err(#TooLowOrderError, ?bid_order, ?current_rate);
                      case (#VolumeStepViolated x) #Err(#VolumeStepViolated(x), ?bid_order, ?current_rate);
                      case (#PriceDigitsOverflow x) #Err(#PriceDigitsOverflow(x), ?bid_order, ?current_rate);
                    };
                  };
                  case (#cancellation(err)) #Err(#CancellationError, ?bid_order, ?current_rate);
                  case (#SessionNumberMismatch x) #Err(#SessionNumberMismatch(x), ?bid_order, ?current_rate);
                  case (#UnknownPrincipal) #Err(#UnknownPrincipal, ?bid_order, ?current_rate);
                  case (#UnknownError) #Err(#UnknownError, ?bid_order, ?current_rate);
                };
              };
            };
            switch (res) {
              case (#Ok(bid_order, rate)) addHistoryItem(pair, ?bid_order, ?rate, "OK");
              case (#Err(err, bid_order, rate)) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(err));
            };
          };
          case (#Err(#ErrorGetRates)) addHistoryItem(pair, null, null, U.getErrorMessage(#RatesError));
        };
      };
    };
  };

  func executeBot() : async () {
    if (is_running == false) {
      return;
    };

    await executeActivityBot();
  };

  func runTimer<system>() : () {
    bot_timer := Timer.recurringTimer<system>(#seconds(bot_timer_interval), executeBot);
  };

  func stopTimer() : () {
    if (bot_timer != 0) {
      Timer.cancelTimer(bot_timer);
      bot_timer := 0;
    };
  };

};
