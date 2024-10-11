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
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
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

  stable var tradingPairsDataV1 : TPR.SharedDataV1 = TPR.defaultSharedDataV1();
  stable let history : Vec.Vector<HistoryModule.HistoryItemType> = Vec.new();

  let tradingPairs : TPR.TradingPairsRegistry = TPR.TradingPairsRegistry();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread_value : Float = 0.05;

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
      tradingPairs.unshare(tradingPairsDataV1);
      let (qp, sp) = await* tradingPairs.refreshTokens(auction, default_spread_value);
      quote_token := ?qp;
      supported_tokens := sp;
      for (pair in tradingPairs.getPairs().vals()) {
        let labels = "base=\"" # pair.base.symbol # "\"";

        ignore metrics.addPullValue("base_credits", labels, func() = pair.base_credits);
        ignore metrics.addPullValue("quote_credits", labels, func() = pair.quote_credits);
        ignore metrics.addPullValue("spread_percent", labels, func() = Int.abs(Float.toInt(0.5 + pair.spread_value * 100)));
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
      tradingPairsDataV1 := tradingPairs.share();
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

  func addHistoryItem(pair : MarketMaker.MarketPair, bidOrder : ?MarketMaker.OrderInfo, askOrder : ?MarketMaker.OrderInfo, rate : ?Float, message : Text) : () {
    let historyItem = HistoryModule.new(pair, bidOrder, askOrder, rate, message);
    Vec.add(history, historyItem);
    Debug.print(HistoryModule.getText(historyItem));
  };

  func cancelAllOrders() : async* {
    #Ok : ();
    #Err : ();
  } {
    let pairs = tradingPairs.getPairs();

    if (pairs.size() == 0) {
      return #Ok;
    };

    let tokens = Array.tabulate<Principal>(
      pairs.size(),
      func(i : Nat) : Principal = pairs[i].base.principal,
    );

    let execute_result = await* auction.removeOrders(tokens);

    switch (execute_result) {
      case (#Ok) {
        addHistoryItem(pairs[0], null, null, null, "ORDERS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(pairs[0], null, null, null, "ORDERS REMOVING ERROR: " # U.getErrorMessage(err));
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

  public func setSpreadValue(baseSymbol : Text, spreadValue : Float) : async () {
    switch (tradingPairs.getPair(baseSymbol)) {
      case (null) throw Error.reject("Base token with symbol \"" # baseSymbol # "\" not found");
      case (?p) {
        p.spread_value := spreadValue;
      };
    };
  };

  public func setQuoteBalance(baseSymbol : Text, balance : Nat) : async () {
    await* tradingPairs.setQuoteBalance(auction, baseSymbol, balance);
  };

  public func executeMarketMaking() : async () {
    await* tradingPairs.refreshCredits(auction);
    for (market_pair in tradingPairs.getPairs().vals()) {
      if (market_pair.base_credits == 0 or market_pair.quote_credits == 0) {
        if (market_pair.base_credits == 0) {
          addHistoryItem(market_pair, null, null, null, "Error processing pair: empty credits for " # Principal.toText(market_pair.base.principal));
        };
        if (market_pair.quote_credits == 0) {
          addHistoryItem(market_pair, null, null, null, "Error processing pair: empty credits for " # Principal.toText(tradingPairs.quoteInfo().principal));
        };
      } else {
        let execute_result = await* MarketMaker.execute(tradingPairs.quoteInfo(), market_pair, oracle, auction);

        switch (execute_result) {
          case (#Ok(bid_order, ask_order, rate)) {
            addHistoryItem(market_pair, ?bid_order, ?ask_order, ?rate, "OK");
          };
          case (#Err(err, bid_order, ask_order, rate)) {
            addHistoryItem(market_pair, bid_order, ask_order, rate, U.getErrorMessage(err));
          };
        };
      };

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
