import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import Iter "mo:base/Iter";
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
import TPR "../market-maker-bot-backend/trading_pairs_registry";
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

  stable var tradingPairsDataV2 : TPR.StableDataV2 = TPR.defaultStableDataV2();

  stable let history : Vec.Vector<HistoryModule.HistoryItemType> = Vec.new();

  let tradingPairs : TPR.TradingPairsRegistry = TPR.TradingPairsRegistry();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread_value : Float = 0.1;

  var bot_timer : Timer.TimerId = 0;

  /// Bot state flags and variables
  stable var bot_timer_interval : Nat = 6 * 60;
  stable var is_running : Bool = false;
  var is_initialized : Bool = false;
  var is_initializing : Bool = false;
  var quote_token : ?Principal = null;
  var supported_tokens : [Principal] = [];
  /// End Bot state flags and variables

  let metrics = PT.PromTracker("", 65);
  metrics.addSystemValues();
  ignore metrics.addPullValue("bot_timer_interval", "", func() = bot_timer_interval);
  ignore metrics.addPullValue("running", "", func() = if (is_running) { 1 } else { 0 });
  ignore metrics.addPullValue("quote_credits", "", tradingPairs.getTotalQuoteCredits);

  func getState() : (BotState) {
    {
      timer_interval = bot_timer_interval;
      running = is_running;
      initialized = is_initialized;
      initializing = is_initializing;
      quote_token = quote_token;
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
      tradingPairs.unshare(tradingPairsDataV2);
      let (qp, sp) = await* tradingPairs.initTokens(auction, default_spread_value);
      quote_token := ?qp;
      supported_tokens := sp;
      for (pair in tradingPairs.getPairs().vals()) {
        let labels = "base=\"" # pair.base.symbol # "\"";

        ignore metrics.addPullValue("base_credits", labels, func() = pair.base_credits);
        ignore metrics.addPullValue("spread_bips", labels, func() = Int.abs(Float.toInt(0.5 + pair.spread_value * 10000)));
      };
      is_initializing := false;
      is_initialized := true;
      #Ok(getState());
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
    if (is_initialized) {
      tradingPairsDataV2 := tradingPairs.share();
    };
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

  func cancelAllOrders() : async* { #Ok : (); #Err : () } {
    let execute_result = await* auction.removeOrders();
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

  /// to make it faster let's not ask about credits here, just return paris list
  /// we will manage credits and funds limit in separate place, so here is we can just return existing data
  public query func getPairsList() : async ([MarketMaker.MarketPairShared]) {
    let pairs = tradingPairs.getPairs();
    Array.tabulate<MarketMaker.MarketPairShared>(
      pairs.size(),
      func(i : Nat) : MarketMaker.MarketPairShared = MarketMaker.sharePair(pairs[i]),
    );
  };

  public query func getHistory(token : ?Principal, limit : Nat, skip : Nat) : async ([HistoryModule.HistoryItemType]) {
    var iter = Vec.valsRev<HistoryModule.HistoryItemType>(history);
    switch (token) {
      case (?t) iter := Iter.filter<HistoryModule.HistoryItemType>(iter, func(x) = switch (x.pair) { case (?_pair) { _pair.base.principal == t }; case (null) { false } });
      case (null) {};
    };
    U.sliceIter(iter, limit, skip);
  };

  public query func getBotState() : async (BotState) {
    getState();
  };

  public query func getQuoteInfo() : async MarketMaker.TokenDescription = async tradingPairs.quoteInfo();

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

  public func notify(token : ?Principal) : async () {
    switch (token) {
      case (?t) ignore await* auction.notify(t);
      case (null) {
        let supported_tokens = await* auction.getSupportedTokens();
        for (token in supported_tokens.vals()) {
          ignore await* auction.notify(token);
        };
      };
    };
    ignore await* tradingPairs.replayTransactionHistory(auction);
    ignore await* tradingPairs.refreshCredits(auction);
  };

  var executionLock : Bool = false;

  public func executeActivityBot() : async () {
    assert not executionLock;
    executionLock := true;
    try {
      let pairs = tradingPairs.getPairs();
      ignore await* tradingPairs.replayTransactionHistory(auction);

      let quote_token = tradingPairs.quoteInfo();

      if (tradingPairs.getTotalQuoteCredits() == 0) {
        addHistoryItem(null, null, null, "Skip processing: empty quote credits");
        executionLock := false;
        return;
      };
      let rates = await* oracle.fetchRates(
        quote_token.symbol,
        pairs |> Array.map<MarketMaker.MarketPair, Text>(_, func(x) = x.base.symbol),
      );

      let placements : Vec.Vector<(MarketMaker.MarketPair, MarketMaker.OrderInfo, Float)> = Vec.new();
      label L for (i in pairs.keys()) {
        let pair = pairs[i];

        switch (rates[i]) {
          case (#Ok _) {};
          case (#Err(#ErrorGetRates(x))) {
            addHistoryItem(?MarketMaker.sharePair(pair), null, null, U.getErrorMessage(#RatesError(x)));
            continue L;
          };
        };

        // calculate multiplicator which help to normalize the price before create
        // the order to the smallest units of the tokens
        let price_decimals_multiplicator : Int32 = Int32.fromNat32(quote_token.decimals) - Int32.fromNat32(pair.base.decimals);
        // get ask price, because in activity bot we want to place higher bid values
        let { ask_price = price } = MarketMaker.getPrices(pair.spread_value, U.requireUpperOk(rates[i]), price_decimals_multiplicator);
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
        Vec.add<(MarketMaker.MarketPair, MarketMaker.OrderInfo, Float)>(placements, (pair, { amount; price }, U.requireUpperOk(rates[i])));
      };

      let replace_orders_result = await* auction.replaceOrders(
        Array.tabulate<(Principal, MarketMaker.OrderInfo, MarketMaker.OrderInfo)>(
          Vec.size(placements),
          func(i) = Vec.get(placements, i) |> (_.0.base.principal, _.1, { amount = 0; price = 0 }),
        ),
        null,
      );

      switch (replace_orders_result) {
        case (#Ok _) {
          for (p in Vec.vals(placements)) {
            addHistoryItem(?MarketMaker.sharePair(p.0), ?p.1, ?p.2, "OK");
          };
        };
        case (#Err(err)) {
          switch (err) {
            case (#placement(err)) {
              let (p, b, r) = Vec.get(placements, err.index);
              let pair = ?MarketMaker.sharePair(p);
              let bid_order = ?b;
              let rate = ?r;
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
