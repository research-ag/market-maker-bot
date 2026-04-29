/// A module which contain implementation of market maker orchestrationg
/// Contain all public methods for bot which helps to manage bot state
/// Manage list of trading pairs, have only one fixed quote asset for all pairs
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Bool "mo:core/Bool";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Float "mo:core/Float";
import Int "mo:core/Int";
import Iter "mo:core/Iter";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Timer "mo:core/Timer";

import PT "mo:promtracker";
import { Tracker } "mo:promtracker";
import PtHttp "mo:promtracker/mixins/http";

import AdminsMixin "../mixins/admins_mixin";

import Auction "./auction_definitions";
import AuctionWrapper "./auction_wrapper";
import CircularBuffer "./CircularBuffer";
import HistoryModule "./history";
import MarketMaker "./market_maker";
import OracleWrapper "./oracle_wrapper";
import TPR "./trading_pairs_registry";
import U "./utils";

persistent actor class MarketMakerBot(auction_be_ : Principal, oracle_be_ : Principal) = self {

  include AdminsMixin(null);

  let auction_principal : Principal = auction_be_;
  let oracle_principal : Principal = oracle_be_;

  var tradingPairsDataV5 : TPR.StableDataV5 = TPR.defaultStableDataV5();

  let history : CircularBuffer.CircularBuffer<HistoryModule.HistoryItemTypeV4> = CircularBuffer.new(65536);

  transient let tradingPairs : TPR.TradingPairsRegistry = TPR.TradingPairsRegistry();
  transient let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  transient let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  transient let default_strategy : MarketMaker.MarketPairStrategy = [((0.02, 0.0), 1.0)];

  transient var bot_timer : Timer.TimerId = 0;

  /// Bot state flags and variables
  var bot_timer_interval : Nat = 6 * 60;
  var is_running : Bool = false;
  transient var is_initialized : Bool = false;
  transient var is_initializing : Bool = false;
  transient var quote_token : ?Principal = null;
  transient var supported_tokens : [Principal] = [];
  /// End Bot state flags and variables

  // a lock that prevents bot to run when set
  transient var system_lock : Bool = false;

  transient let pt = PT.Tracker.new();
  transient let renderer = PT.Renderer();
  renderer.addValue(pt.toValue());
  renderer.addCanisterLabel(self);
  include PtHttp(renderer.renderExposition, "/metrics");

  renderer.addValue(PT.allSystemMetrics);
  renderer.addValue(
    [
      PT.newValue("bot_timer_interval", [], func() = bot_timer_interval),
      PT.newValue("running", [], func() = if (is_running) { 1 } else { 0 }),
      PT.newValue("quote_reserve", [], tradingPairs.getQuoteReserve),
      PT.newValue("history_length", [], func() = history.size()),
    ].bundle([])
  );

  transient var tradingPairStrategyMetrics : ?Nat = null;
  func updateTradingPairsMetrics() {
    // remove existing metrics
    switch (tradingPairStrategyMetrics) {
      case (?m) renderer.removeValue(m);
      case (null) {};
    };
    // register metrics
    let pairs = tradingPairs.getPairs();

    tradingPairStrategyMetrics := ?renderer.addValueRef(
      Array.map(
        pairs,
        func(pair) = Array.tabulate(
          pair.strategy.size(),
          func(j) = [
            PT.newValue("spread_bips", [], func() = Int.abs(Float.toInt(0.5 + pair.strategy[j].0.0 * 10000))),
            PT.newValue("spread_base_bips", [], func() = Int.abs(Float.toInt(0.5 + (1.0 + pair.strategy[j].0.1) * 10000))),
            PT.newValue("spread_weight_bips", [], func() = Int.abs(Float.toInt(pair.strategy[j].1 * 10000))),
          ].bundle([("index", Nat.toText(j))]),
        ).bundle([("base", pair.base.symbol)]),
      ).bundle([])
    );
  };

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
      tradingPairs.unshare(tradingPairsDataV5);
      let (qp, sp) = await* tradingPairs.initTokens(auction, default_strategy);
      quote_token := ?qp;
      supported_tokens := sp;
      for (pair in tradingPairs.getPairs().vals()) {
        renderer.addValue(
          [
            PT.newValue("base_credits", [], func() = pair.base_credits),
            PT.newValue("quote_credits", [], func() = pair.quote_credits),
          ].bundle([("base", pair.base.symbol)])
        );
      };

      updateTradingPairsMetrics();
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

  system func preupgrade() {
    Debug.print("Preupgrade");
    if (is_initialized) {
      tradingPairsDataV5 := tradingPairs.share();
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

  func addHistoryItem(pair : ?MarketMaker.MarketPairShared, bidOrder : ?MarketMaker.OrderInfo, askOrder : ?MarketMaker.OrderInfo, rate : ?Float, message : Text) : () {
    let historyItem = HistoryModule.new(pair, bidOrder, askOrder, rate, message);
    history.add(historyItem);
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

  public query func getHistory(token : ?Principal, limit : Nat, skip : Nat) : async ([HistoryModule.HistoryItemTypeV4]) {
    var iter = history.reverseAvailableValues();
    switch (token) {
      case (?t) iter := iter.filter(func(x) = switch (x.pair) { case (?_pair) { _pair.base.principal == t }; case (null) { false } });
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
    assert not system_lock;
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

  public shared ({ caller }) func updatePriceStrategy(baseSymbol : Text, strategy : MarketMaker.MarketPairStrategy) : async () {
    await* assertAdminAccess(caller);
    switch (tradingPairs.getPair(baseSymbol)) {
      case (null) throw Error.reject("Base token with symbol \"" # baseSymbol # "\" not found");
      case (?p) {
        var totalWeight : Float = 0;
        for ((_, w) in strategy.vals()) {
          totalWeight += w;
          if (totalWeight > 1) {
            throw Error.reject("Strategy weights have to sum up to value less or equal than 1.0");
          };
        };
        p.strategy := strategy;
      };
    };
    updateTradingPairsMetrics();
  };

  public query func queryQuoteReserve() : async Nat = async tradingPairs.getQuoteReserve();

  public shared ({ caller }) func setQuoteBalance(baseSymbol : Text, balance : { #set : Nat; #inc : Nat; #dec : Nat }) : async Nat {
    await* assertAdminAccess(caller);
    await* tradingPairs.setQuoteBalance(auction, baseSymbol, balance);
  };

  public shared ({ caller }) func notify(token : ?Principal) : async () {
    await* assertAdminAccess(caller);
    switch (token) {
      case (?t) ignore await* auction.notify([t]);
      case (null) {
        let supported_tokens = await* auction.getSupportedTokens();
        ignore await* auction.notify(supported_tokens);
      };
    };
    ignore await* tradingPairs.replayTransactionHistory(auction);
  };

  transient var executionLock : Bool = false;

  public shared ({ caller }) func executeMarketMaking() : async () {
    await* assertAdminAccess(caller);
    await* executeMarketMaking_();
  };

  func executeMarketMaking_() : async* () {
    assert not system_lock;
    assert not executionLock;
    executionLock := true;
    try {
      let pairs = tradingPairs.getPairs();
      let rates = await* oracle.fetchRates(
        tradingPairs.quoteInfo().symbol,
        pairs |> Array.map<MarketMaker.MarketPair, Text>(_, func(x) = x.base.symbol),
      );
      let accountRevision = await* tradingPairs.replayTransactionHistory(auction);

      let pairsToProcess : List.List<MarketMaker.MarketPair> = List.empty();
      let ratesToProcess : List.List<Float> = List.empty();
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
          List.add(pairsToProcess, market_pair);
          List.add(ratesToProcess, U.requireUpperOk(rates[i]));
        };
      };
      let execute_result = await* MarketMaker.execute(tradingPairs.quoteInfo(), List.toArray(pairsToProcess), List.toArray(ratesToProcess), auction, accountRevision);

      switch (execute_result) {
        case (#Ok results) {
          for (i in results.keys()) {
            let (bids, asks, rate) = results[i];
            for (j in Nat.range(0, Nat.max(bids.size(), asks.size()) - 1)) {
              addHistoryItem(
                ?MarketMaker.sharePair(List.at(pairsToProcess, i)),
                if (j < bids.size()) { ?bids[j] } else { null },
                if (j < asks.size()) { ?asks[j] } else { null },
                ?rate,
                "OK",
              );
            };
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

  public shared ({ caller }) func notify_another_auction(auction : Principal) : async () {
    await* assertAdminAccess(caller);
    assert auction != auction_principal;

    let ac : AuctionWrapper.Self = AuctionWrapper.Self(auction);
    let supported_tokens = await* ac.getSupportedTokens();
    ignore await* ac.notify(supported_tokens);
  };

  public shared ({ caller }) func migrate_auction_credits(source_auction : Principal, dest_auction : Principal) : async Text {
    await* assertAdminAccess(caller);
    assert not is_running;
    assert not system_lock;
    system_lock := true;
    let qt = U.require(quote_token);
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

    try {
      ignore await src.manageOrders(?#all(null), [], null);
      let { credits } = await src.auction_query(
        [],
        { Auction.EMPTY_QUERY with credits = ?true },
      );
      let calls : List.List<(Principal, async Auction.WithdrawResponse, ?MarketMaker.MarketPair)> = List.empty();
      try {
        for ((token, acc) in credits.vals()) {
          List.add(
            calls,
            (
              token,
              src.icrc84_withdraw({
                to = { owner = dest_auction; subaccount = ?destSubaccount };
                amount = acc.available;
                token;
                expected_fee = null;
              }),
              tradingPairs.getPairByLedger(token),
            ),
          );
        };
      } catch (err) {
        Debug.print("migrate_auction_credits scheduling calls error: " # Error.message(err));
      };
      for ((token, call, pair) in List.values(calls)) {
        try {
          switch (await call) {
            case (#Ok _) switch (pair) {
              case (?p) p.base_credits := 0;
              case (null) if (Principal.equal(token, qt)) {
                for (p in tradingPairs.getPairs().vals()) {
                  p.quote_credits := 0;
                };
                tradingPairs.quoteReserve := 0;
              };
            };
            case (#Err err) Debug.print("migrate_auction_credits error for token " # Principal.toText(token) # ": " # debug_show err);
          };
        } catch (err) {
          Debug.print("migrate_auction_credits error for token " # Principal.toText(token) # ": " # Error.message(err));
        };
      };
    } catch (err) {
      return Error.message(err);
    } finally {
      system_lock := false;
    };
    "Ok";
  };

  func executeBot() : async () {
    if (is_running == false) {
      return;
    };

    await* executeMarketMaking_();
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
