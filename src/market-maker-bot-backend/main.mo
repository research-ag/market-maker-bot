/// A module which contain implementation of market maker orchestrationg
/// Contain all public methods for bot which helps to manage bot state
/// Manage list of trading pairs, have only one fixed quote asset for all pairs
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import RBTree "mo:base/RBTree";
import Text "mo:base/Text";
import Timer "mo:base/Timer";

import PT "mo:promtracker";
import Vec "mo:vector";

import Auction "./auction_definitions";
import AuctionWrapper "./auction_wrapper";
import HistoryModule "./history";
import HTTP "./http";
import MarketMaker "./market_maker";
import OracleWrapper "./oracle_wrapper";
import TPR "./trading_pairs_registry";
import U "./utils";

actor class MarketMakerBot(auction_be_ : Principal, oracle_be_ : Principal) = self {

  stable let auction_principal : Principal = auction_be_;
  stable let oracle_principal : Principal = oracle_be_;

  stable var tradingPairsDataV2 : TPR.StableDataV2 = TPR.defaultStableDataV2();
  stable var tradingPairsDataV3 : TPR.StableDataV3 = TPR.migrateStableDataV3(tradingPairsDataV2);

  stable let historyV2 : Vec.Vector<HistoryModule.HistoryItemTypeV2> = Vec.new();
  stable let historyV3 : Vec.Vector<HistoryModule.HistoryItemTypeV3> = Vec.map<HistoryModule.HistoryItemTypeV2, HistoryModule.HistoryItemTypeV3>(
    historyV2,
    func(x) : HistoryModule.HistoryItemTypeV3 = {
      x with
      pair = switch (x.pair) {
        case (?p) (?{ p with spread = (p.spread_value, 0.0) });
        case (null) null;
      };
    },
  );

  let tradingPairs : TPR.TradingPairsRegistry = TPR.TradingPairsRegistry();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread : (value : Float, bias : Float) = (0.05, 0.0);

  var bot_timer : Timer.TimerId = 0;

  /// Bot state flags and variables
  stable var bot_timer_interval : Nat = 6 * 60;
  stable var is_running : Bool = false;
  var is_initialized : Bool = false;
  var is_initializing : Bool = false;
  var quote_token : ?Principal = null;
  var supported_tokens : [Principal] = [];
  /// End Bot state flags and variables

  stable var stableAdminsMap = RBTree.RBTree<Principal, ()>(Principal.compare).share();
  switch (RBTree.size(stableAdminsMap)) {
    case (0) {
      let adminsMap = RBTree.RBTree<Principal, ()>(Principal.compare);
      adminsMap.put(Principal.fromText("2vxsx-fae"), ());
      stableAdminsMap := adminsMap.share();
    };
    case (_) {};
  };
  let adminsMap = RBTree.RBTree<Principal, ()>(Principal.compare);
  adminsMap.unshare(stableAdminsMap);

  let metrics = PT.PromTracker("", 65);
  metrics.addSystemValues();
  ignore metrics.addPullValue("bot_timer_interval", "", func() = bot_timer_interval);
  ignore metrics.addPullValue("running", "", func() = if (is_running) { 1 } else { 0 });
  ignore metrics.addPullValue("quote_reserve", "", tradingPairs.getQuoteReserve);

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
      tradingPairs.unshare(tradingPairsDataV3);
      let (qp, sp) = await* tradingPairs.initTokens(auction, default_spread);
      quote_token := ?qp;
      supported_tokens := sp;
      for (pair in tradingPairs.getPairs().vals()) {
        let labels = "base=\"" # pair.base.symbol # "\"";

        ignore metrics.addPullValue("base_credits", labels, func() = pair.base_credits);
        ignore metrics.addPullValue("quote_credits", labels, func() = pair.quote_credits);
        ignore metrics.addPullValue("spread_bips", labels, func() = Int.abs(Float.toInt(0.5 + pair.spread.0 * 10000)));
        ignore metrics.addPullValue("spread_bias_bips", labels, func() = Int.abs(Float.toInt(0.5 + pair.spread.1 * 10000)));
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
      tradingPairsDataV3 := tradingPairs.share();
    };
    stableAdminsMap := adminsMap.share();
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

  public query func listAdmins() : async [Principal] = async adminsMap.entries()
  |> Iter.map<(Principal, ()), Principal>(_, func((p, _)) = p)
  |> Iter.toArray(_);

  private func assertAdminAccess(principal : Principal) : async* () {
    if (adminsMap.get(principal) == null) {
      throw Error.reject("No Access for this principal " # Principal.toText(principal));
    };
  };

  public shared ({ caller }) func addAdmin(principal : Principal) : async () {
    await* assertAdminAccess(caller);
    adminsMap.put(principal, ());
  };

  public shared ({ caller }) func removeAdmin(principal : Principal) : async () {
    if (Principal.equal(principal, caller)) {
      throw Error.reject("Cannot remove yourself from admins");
    };
    await* assertAdminAccess(caller);
    adminsMap.delete(principal);
  };

  func addHistoryItem(pair : ?MarketMaker.MarketPairShared, bidOrder : ?MarketMaker.OrderInfo, askOrder : ?MarketMaker.OrderInfo, rate : ?Float, message : Text) : () {
    let historyItem = HistoryModule.new(pair, bidOrder, askOrder, rate, message);
    Vec.add(historyV3, historyItem);
    Debug.print(HistoryModule.getText(historyItem));
  };

  func cancelAllOrders() : async* { #Ok : (); #Err : () } {
    let execute_result = await* auction.removeOrders();
    switch (execute_result) {
      case (#Ok) {
        addHistoryItem(null, null, null, null, "ORDERS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(null, null, null, null, "ORDERS REMOVING ERROR: " # U.getErrorMessage(err));
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

  public query func getHistory(token : ?Principal, limit : Nat, skip : Nat) : async ([HistoryModule.HistoryItemTypeV3]) {
    var iter = Vec.valsRev<HistoryModule.HistoryItemTypeV3>(historyV3);
    switch (token) {
      case (?t) iter := Iter.filter<HistoryModule.HistoryItemTypeV3>(iter, func(x) = switch (x.pair) { case (?_pair) { _pair.base.principal == t }; case (null) { false } });
      case (null) {};
    };
    U.sliceIter(iter, limit, skip);
  };

  public query func getBotState() : async (BotState) {
    getState();
  };

  public query func getQuoteInfo() : async MarketMaker.TokenDescription = async tradingPairs.quoteInfo();

  public shared ({ caller }) func startBot(timer_interval : Nat) : async {
    #Ok : (BotState);
    #Err : ({
      #NotInitializedError;
      #AlreadyStartedError;
    });
  } {
    await* assertAdminAccess(caller);
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

  public shared ({ caller }) func stopBot() : async {
    #Ok : (BotState);
    #Err : ({
      #NotInitializedError;
      #AlreadyStopedError;
      #CancelOrdersError;
    });
  } {
    await* assertAdminAccess(caller);
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

  public shared ({ caller }) func setSpread(baseSymbol : Text, spreadValue : Float, spreadBias : Float) : async () {
    await* assertAdminAccess(caller);
    switch (tradingPairs.getPair(baseSymbol)) {
      case (null) throw Error.reject("Base token with symbol \"" # baseSymbol # "\" not found");
      case (?p) {
        p.spread := (spreadValue, spreadBias);
      };
    };
  };

  public query func queryQuoteReserve() : async Nat = async tradingPairs.getQuoteReserve();

  public shared ({ caller }) func setQuoteBalance(baseSymbol : Text, balance : { #set : Nat; #inc : Nat; #dec : Nat }) : async Nat {
    await* assertAdminAccess(caller);
    await* tradingPairs.setQuoteBalance(auction, baseSymbol, balance);
  };

  public shared ({ caller }) func notify(token : ?Principal) : async () {
    await* assertAdminAccess(caller);
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

  public shared ({ caller }) func executeMarketMaking() : async () {
    await* assertAdminAccess(caller);
    assert not executionLock;
    executionLock := true;
    try {
      let pairs = tradingPairs.getPairs();
      let rates = await* oracle.fetchRates(
        tradingPairs.quoteInfo().symbol,
        pairs |> Array.map<MarketMaker.MarketPair, Text>(_, func(x) = x.base.symbol),
      );
      let sessionNumber = await* tradingPairs.replayTransactionHistory(auction);

      let pairsToProcess : Vec.Vector<MarketMaker.MarketPair> = Vec.new();
      let ratesToProcess : Vec.Vector<Float> = Vec.new();
      for (i in pairs.keys()) {
        let market_pair = pairs[i];
        if (market_pair.base_credits == 0 or market_pair.quote_credits == 0 or U.upperResultToOption(rates[i]) == null) {
          if (U.upperResultToOption(rates[i]) == null) {
            switch (rates[i]) {
              case (#Ok _) {};
              case (#Err(#ErrorGetRates(x))) addHistoryItem(?MarketMaker.sharePair(market_pair), null, null, null, U.getErrorMessage(#RatesError(x)));
            };
          } else if (market_pair.base_credits == 0) {
            addHistoryItem(?MarketMaker.sharePair(market_pair), null, null, null, "Skip processing pair: empty credits for " # Principal.toText(market_pair.base.principal));
          } else if (market_pair.quote_credits == 0) {
            addHistoryItem(?MarketMaker.sharePair(market_pair), null, null, null, "Skip processing pair: empty credits for " # Principal.toText(tradingPairs.quoteInfo().principal));
          };
        } else {
          Vec.add(pairsToProcess, market_pair);
          Vec.add(ratesToProcess, U.requireUpperOk(rates[i]));
        };
      };
      let execute_result = await* MarketMaker.execute(tradingPairs.quoteInfo(), Vec.toArray(pairsToProcess), Vec.toArray(ratesToProcess), auction, sessionNumber);

      switch (execute_result) {
        case (#Ok results) {
          for (i in results.keys()) {
            let (bid_order, ask_order, rate) = results[i];
            addHistoryItem(?MarketMaker.sharePair(Vec.get(pairsToProcess, i)), ?bid_order, ?ask_order, ?rate, "OK");
          };
        };
        case (#Err(err, market_pair, bid_order, ask_order, rate)) {
          addHistoryItem(market_pair, bid_order, ask_order, rate, U.getErrorMessage(err));
        };
      };
    } finally {
      executionLock := false;
    };
  };

  public shared ({ caller }) func migrate_auction_credits(source_auction : Principal, dest_auction : Principal) : async Text {
    await* assertAdminAccess(caller);
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

  func executeBot() : async () {
    if (is_running == false) {
      return;
    };

    await executeMarketMaking();
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
