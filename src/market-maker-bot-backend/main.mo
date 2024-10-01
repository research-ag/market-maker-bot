/// A module which contain implementation of market maker orchestrationg
/// Contain all public methods for bot which helps to manage bot state
/// Manage list of trading pairs, have only one fixed quote asset for all pairs
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Bool "mo:base/Bool";
import Nat "mo:base/Nat";

import MarketMakerModule "./market_maker";
import HistoryModule "./history";
import Tokens "./tokens";
import OracleWrapper "./oracle_wrapper";
import MarketMaker "./market_maker";
import AuctionWrapper "./auction_wrapper";
import Auction "./auction_definitions";
import U "./utils";

actor class MarketMakerBot(auction_be_ : Principal, oracle_be_ : Principal) = self {

  stable let auction_principal : Principal = auction_be_;
  stable let oracle_principal : Principal = oracle_be_;

  let tokens_info : AssocList.AssocList<Principal, Tokens.TokenInfo> = Tokens.getTokensInfo();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread_value : Float = 0.05;

  var market_pairs : [MarketMakerModule.MarketPair] = [];
  var history : [HistoryModule.HistoryItem] = [];
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
                  market_pairs := Array.append(market_pairs, [getMarketPair(token, quote_token, null)]);
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
    let historyItem = HistoryModule.HistoryItem(pair, bidOrder, askOrder, rate, message);
    history := Array.append(
      history,
      [historyItem],
    );
    Debug.print(historyItem.getText());
  };

  func getMarketPair(base : Principal, quote : Principal, token_credits : AssocList.AssocList<Principal, Nat>) : (MarketMakerModule.MarketPair) {
    let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, base, Principal.equal, "Error get base token info");
    let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, quote, Principal.equal, "Error get quote token info");

    {
      base_principal = base;
      base_symbol = base_token_info.symbol;
      base_decimals = base_token_info.decimals;
      base_credits = U.getByKeyOrDefault<Principal, Nat>(token_credits, base, Principal.equal, 0);
      quote_principal = quote;
      quote_symbol = quote_token_info.symbol;
      quote_decimals = quote_token_info.decimals;
      quote_credits = U.getByKeyOrDefault<Principal, Nat>(token_credits, quote, Principal.equal, 0);
      spread_value = default_spread_value;
    };
  };

  func cancelAllOrders() : async* {
    #Ok : ();
    #Err : ();
  } {
    let size = market_pairs.size();

    if (size == 0) {
      return #Ok;
    };

    let tokens = Array.tabulate<Principal>(
      size,
      func(i : Nat) : Principal = market_pairs[i].base_principal,
    );

    let execute_result = await* auction.removeOrders(tokens);

    switch (execute_result) {
      case (#Ok) {
        addHistoryItem(market_pairs[0], null, null, null, "ORDERS REMOVED");
        return #Ok;
      };
      case (#Err(err)) {
        addHistoryItem(market_pairs[0], null, null, null, "ORDERS REMOVING ERROR: " # U.getErrorMessage(err));
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

  public func queryBotCredits() : async [(Principal, { total : Nat; locked : Nat; available : Nat })] {
    await auction.getAuction().queryCredits();
  };

  public func queryBotBids() : async [(
    Nat,
    {
      icrc1Ledger : Principal;
      price : Float;
      volume : Nat;
    },
  )] {
    await auction.getAuction().queryBids();
  };

  public func queryBotAsks() : async [(
    Nat,
    {
      icrc1Ledger : Principal;
      price : Float;
      volume : Nat;
    },
  )] {
    await auction.getAuction().queryAsks();
  };

  func getCredits() : async* (AssocList.AssocList<Principal, Nat>) {
    /// here will be logic for calculating available credits for each pair
    /// based on the current state of the auction, quote credit limit and already placed orders
    /// temporary just simple return quote token credits divided by pairs count
    await* notifyCreditUpdates();
    let token_credits : AssocList.AssocList<Principal, Nat> = await* auction.getCredits();
    switch (quote_token) {
      case (?quote_token) {
        let size = market_pairs.size();
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
  public query func getPairsList() : async ([MarketMaker.MarketPair]) {
    let size = market_pairs.size();
    // let token_credits = await* getCredits();
    Array.tabulate<MarketMaker.MarketPair>(
      size,
      func(i : Nat) : MarketMaker.MarketPair = getMarketPair(market_pairs[i].base_principal, market_pairs[i].quote_principal, null),
    );
  };

  public query func getHistory() : async ([HistoryModule.HistoryItemType]) {
    let size = history.size();
    Array.tabulate<HistoryModule.HistoryItemType>(
      size,
      func(i : Nat) : HistoryModule.HistoryItemType = history[i].getItem(),
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

  public func executeMarketMaking() : async () {
    var i : Nat = 0;
    let size = market_pairs.size();
    let token_credits = await* getCredits();

    while (i < size) {
      let market_pair = getMarketPair(market_pairs[i].base_principal, market_pairs[i].quote_principal, token_credits);

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

      i := i + 1;
    };
  };

  public func migrate_auction_credits(source_auction : Principal, dest_auction : Principal) : async Text {
    assert not is_running;
    let src : Auction.Self = actor (Principal.toText(source_auction));
    let dest : Auction.Self = actor (Principal.toText(dest_auction));
    let destSubaccount = await dest.principalToSubaccount(Principal.fromActor(self));
    ignore await src.manageOrders(? #all(null), []);
    let credits = await src.queryCredits();
    for ((_, acc) in credits.vals()) {
      assert acc.locked == 0;
    };
    for ((token, acc) in credits.vals()) {
      ignore await src.icrc84_withdraw({
        to = { owner = dest_auction; subaccount = destSubaccount };
        amount = acc.available;
        token;
        expected_fee = null;
      });
      try {
        ignore await dest.icrc84_notify({ token });
      } catch (_) {
        // pass
      };
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
