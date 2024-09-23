/// A module which contain implementation of market maker orchestrationg
/// Contain all public methods for bot which helps to manage bot state
/// Manage list of trading pairs, have only one fixed quote asset for all pairs
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";
import List "mo:base/List";

import Vec "mo:vector";

import MarketMakerModule "./market_maker";
import HistoryModule "./history";
import Tokens "./tokens";
import OracleWrapper "./oracle_wrapper";
import MarketMaker "./market_maker";
import AuctionWrapper "./auction_wrapper";
import U "./utils";

actor class MarketMakerBot(auction_be_ : Principal, oracle_be_ : Principal) = self {

  stable let auction_principal : Principal = auction_be_;
  stable let oracle_principal : Principal = oracle_be_;

  stable var marketPairs : AssocList.AssocList<(quoteSymbol : Text, baseSymbol : Text), MarketMakerModule.MarketPair> = null;
  stable let history : Vec.Vector<HistoryModule.HistoryItemType> = Vec.new();

  let tokens_info : AssocList.AssocList<Principal, Tokens.TokenInfo> = Tokens.getTokensInfo();
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
      quote_token := ?(await* auction.getQuoteToken());
      supported_tokens := await* auction.getSupportedTokens();

      switch (quote_token) {
        case (?quote_token) {
          for (token in supported_tokens.vals()) {
            if (Principal.equal(token, quote_token) == false) {
              switch (AssocList.find(tokens_info, token, Principal.equal)) {
                case (?_) {
                  let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, token, Principal.equal, "Error get base token info");
                  let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, quote_token, Principal.equal, "Error get quote token info");
                  let pair = {
                    base_principal = token;
                    base_symbol = base_token_info.symbol;
                    base_decimals = base_token_info.decimals;
                    var base_credits = 0;
                    quote_principal = quote_token;
                    quote_symbol = quote_token_info.symbol;
                    quote_decimals = quote_token_info.decimals;
                    var quote_credits = 0;
                    var spread_value = default_spread_value;
                  };

                  let (upd, oldValue) = AssocList.replace<(quoteSymbol : Text, baseSymbol : Text), MarketMakerModule.MarketPair>(
                    marketPairs,
                    (pair.quote_symbol, pair.base_symbol),
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
          is_initialized := true;
          is_initializing := false;
          return #Ok(getState());
        };
        case (null) {
          is_initializing := false;
          return #Err(#UnknownQuoteTokenError);
        };
      };
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

  func addHistoryItem(pair : MarketMakerModule.MarketPair, bidOrder : ?MarketMakerModule.OrderInfo, askOrder : ?MarketMakerModule.OrderInfo, rate : ?Float, message : Text) : () {
    let historyItem = HistoryModule.new(pair, bidOrder, askOrder, rate, message);
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
      func(i : Nat) : Principal = pairs[i].1.base_principal,
    );

    let execute_result = await* auction.removeOrders(tokens);

    switch (execute_result) {
      case (#Ok) {
        addHistoryItem(pairs[0].1, null, null, null, "ORDERS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(pairs[0].1, null, null, null, "ORDERS REMOVING ERROR: " # U.getErrorMessage(err));
        return #Err;
      };
    };
  };

  func notifyCreditUpdates() : async* () {
    let supported_tokens = await* auction.getSupportedTokens();
    for (token in supported_tokens.vals()) {
      ignore await* auction.notify(token);
    };
  };

  func getCredits() : async* (AssocList.AssocList<Principal, Nat>) {
    /// here will be logic for calculating available credits for each pair
    /// based on the current state of the auction, quote credit limit and already placed orders
    /// temporary just simple return quote token credits divided by pairs count
    await* notifyCreditUpdates();
    let token_credits : AssocList.AssocList<Principal, Nat> = await* auction.getCredits();
    switch (quote_token) {
      case (?quote_token) {
        let size = List.size(marketPairs);
        if (size == 0) {
          return token_credits;
        };
        let quote_token_credits : Nat = U.getByKeyOrDefault<Principal, Nat>(token_credits, quote_token, Principal.equal, 0) / size;
        return AssocList.replace<Principal, Nat>(token_credits, quote_token, Principal.equal, ?quote_token_credits).0;
      };
      case (null) {
        return token_credits;
      };
    };

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

  public func updateSpreadValue(baseToken : Text, spreadValue : Float) : async () {
    if (not is_initialized) {
      return throw Error.reject("Not initialized");
    };
    let pair = AssocList.find<(quoteSymbol : Text, baseSymbol : Text), MarketMakerModule.MarketPair>(
      marketPairs,
      (baseToken, baseToken),
      func((_, b1), (_, b2)) = Text.equal(b1, b2),
    );
    switch (pair) {
      case (null) throw Error.reject("Base token with symbol \"" # baseToken # "\" not found");
      case (?p) {
        p.spread_value := spreadValue;
      };
    };
  };

  public func executeMarketMaking() : async () {
    let token_credits = await* getCredits();

    for ((_, market_pair) in List.toIter(marketPairs)) {

      market_pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(token_credits, market_pair.base_principal, Principal.equal, 0);
      market_pair.quote_credits := U.getByKeyOrDefault<Principal, Nat>(token_credits, market_pair.quote_principal, Principal.equal, 0);

      if (market_pair.base_credits == 0 or market_pair.quote_credits == 0) {
        if (market_pair.base_credits == 0) {
          addHistoryItem(market_pair, null, null, null, "Error processing pair: empty credits for " # Principal.toText(market_pair.base_principal));
        };
        if (market_pair.quote_credits == 0) {
          addHistoryItem(market_pair, null, null, null, "Error processing pair: empty credits for " # Principal.toText(market_pair.quote_principal));
        };
      } else {
        let execute_result = await* MarketMaker.execute(market_pair, oracle, auction);

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
