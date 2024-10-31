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
  ignore metrics.addPullValue("quote_credits", "", func() = switch (marketPairs) { case (?(p, _)) { p.1.quote_credits }; case (_) { 0 } });

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
              let pair : MarketMaker.MarketPair = {
                base = {
                  principal = token;
                  symbol = base_token_info.symbol;
                  decimals = base_token_info.decimals;
                };
                var base_credits = 0;
                var quote_credits = 0;
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

  func addHistoryItem(pair : ?MarketMaker.MarketPairShared, bidOrder : ?MarketMaker.OrderInfo, rate : ?Float, message : Text) : () {
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
        addHistoryItem(null, null, null, "BIDS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(null, null, null, "BIDS REMOVING ERROR: " # U.getErrorMessage(err));
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
    let historySize = Vec.size(history);
    let size : Int = historySize - skip;
    if (size < 1) return [];
    Array.tabulate<HistoryModule.HistoryItemType>(
      Nat.min(Int.abs(size), limit),
      func(i : Nat) : HistoryModule.HistoryItemType = Vec.get(history, Int.abs(historySize - skip - i - 1)),
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

  var executionLock : Bool = false;

  public func executeActivityBot() : async () {
    assert not executionLock;
    executionLock := true;

    try {
      let quote_credits = await* getQuoteCredit();
      let quote_token = U.requireMsg(quote, "Not initialized");
      let pairs = List.toArray(marketPairs);

      if (quote_credits == 0) {
        addHistoryItem(null, null, null, "Skip processing: empty quote credits");
        executionLock := false;
        return;
      };

      let ?rates = await* oracle.fetchRates(
        pairs[0].0.0,
        pairs |> Array.map<((Text, Text), MarketMaker.MarketPair), Text>(_, func(x) = x.1.base.symbol),
      ) else {
        addHistoryItem(null, null, null, U.getErrorMessage(#RatesError));
        executionLock := false;
        return;
      };

      let bids : [var MarketMaker.OrderInfo] = Array.init<MarketMaker.OrderInfo>(pairs.size(), { amount = 0; price = 0 });
      for (i in pairs.keys()) {
        let pair = pairs[i].1;
        pair.quote_credits := quote_credits;
        let current_rate = rates[i];

        // calculate multiplicator which help to normalize the price before create
        // the order to the smallest units of the tokens
        let price_decimals_multiplicator : Int32 = Int32.fromNat32(quote_token.decimals) - Int32.fromNat32(pair.base.decimals);
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
        bids[i] := { amount; price };
      };

      let replace_orders_result = await* auction.replaceOrders(
        Array.tabulate<(Principal, MarketMaker.OrderInfo, MarketMaker.OrderInfo)>(
          pairs.size(),
          func(i) = (pairs[i].1.base.principal, bids[i], { amount = 0; price = 0 }),
        ),
        null,
      );

      switch (replace_orders_result) {
        case (#Ok results) {
          for (i in results.keys()) {
            addHistoryItem(?MarketMaker.sharePair(pairs[i].1), ?bids[i], ?rates[i], "OK");
          };
        };
        case (#Err(err)) {
          switch (err) {
            case (#placement(err)) {
              let pair = ?MarketMaker.sharePair(pairs[err.index].1);
              let bid_order = ?bids[err.index];
              let rate = ?rates[err.index];
              switch (err.error) {
                case (#ConflictingOrder(_)) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#ConflictOrderError));
                case (#UnknownAsset) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#UnknownAssetError));
                case (#NoCredit) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#NoCreditError));
                case (#TooLowOrder) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#TooLowOrderError));
                case (#VolumeStepViolated x) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#VolumeStepViolated(x)));
                case (#PriceDigitsOverflow x) addHistoryItem(pair, bid_order, rate, U.getErrorMessage(#PriceDigitsOverflow(x)));
              };
            };
            case (#cancellation(err)) addHistoryItem(null, null, null, U.getErrorMessage(#CancellationError));
            case (#SessionNumberMismatch x) addHistoryItem(null, null, null, U.getErrorMessage(#SessionNumberMismatch(x)));
            case (#UnknownPrincipal) addHistoryItem(null, null, null, U.getErrorMessage(#UnknownPrincipal));
            case (#UnknownError x) addHistoryItem(null, null, null, U.getErrorMessage(#UnknownError(x)));
          };
        };
      };
    } finally {
      executionLock := false;
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
