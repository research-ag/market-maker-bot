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
import MarketMaker "market_maker";
import AuctionWrapper "./auction_wrapper";
import U "./utils";

actor class MarketMakerBot(auction_be_: Principal, oracle_be_: Principal) = self {

  stable let auction_principal : Principal = auction_be_;
  stable let oracle_principal : Principal = oracle_be_;

  let tokens_info : AssocList.AssocList<Principal, Tokens.TokenInfo> = Tokens.getTokensInfo();
  let auction : AuctionWrapper.Self = AuctionWrapper.Self(auction_principal);
  let oracle : OracleWrapper.Self = OracleWrapper.Self(oracle_principal);
  let default_spread_value : Float = 0.05;

  var is_initialized : Bool = false;
  var is_running : Bool = false;
  var market_pairs : [MarketMakerModule.MarketPair] = [];
  var history : [HistoryModule.HistoryItem] = [];

  public func init() : async () {
    if (is_initialized == false) {
      Debug.print("Init bot: " # Principal.toText(auction_principal) # " " # Principal.toText(oracle_principal));
      let quote_token = await* auction.getQuoteToken();
      let supported_tokens = await* auction.getSupportedTokens();
      Debug.print("Quote token: " # Principal.toText(quote_token));
      Debug.print("Supported tokens: " # debug_show(supported_tokens));

      for (token in supported_tokens.vals()) {
        if (Principal.equal(token, quote_token) == false) {
          switch (AssocList.find(tokens_info, token, Principal.equal)) {
            case (?token_info) {
              market_pairs := Array.append(market_pairs, [getMarketPair(token, quote_token, null)]);
            };
            case (_) {};
          };
        };
      };

      is_initialized := true;
    } else {
      Debug.print("Bot already initialized");
    }
  };

  public type BotState = {
    running : Bool;
  };

  system func preupgrade() {
    bot_running_state := is_running;
    Debug.print("Preupgrade");
  };

  system func postupgrade() {
    Debug.print("Postupgrade");
    is_running := bot_running_state;
    ignore Timer.setTimer<system>(#seconds (0), func(): async () {
      Debug.print("Init fired");
      await init();
    });
  };

  stable var bot_running_state : Bool = is_running;

  func addHistoryItem(pair : MarketMakerModule.MarketPair, bidOrder : MarketMakerModule.OrderInfo, askOrder : MarketMakerModule.OrderInfo, message : Text) : () {
    let historyItem = HistoryModule.HistoryItem(pair, bidOrder, askOrder, message);
    history := Array.append(
      history,
      [historyItem],
    );
    Debug.print(historyItem.getText());
  };

  func setBotState(running : Bool) : async* (BotState) {
    is_running := running;

    {
      running = is_running;
    };
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

  func cancelAllOrders() : async* () {
    var i : Nat = 0;
    let size = market_pairs.size();
    let empty_order : MarketMakerModule.OrderInfo = {
      amount = 0;
      price = 0.0;
    };

    while (i < size) {
      let execute_result = await* auction.removeOrders(market_pairs[i].base_principal);

      switch (execute_result) {
        case (#Ok) {
          addHistoryItem(market_pairs[i], empty_order, empty_order, "ORDERS REMOVED");
        };
        case (#Err(err)) {
          addHistoryItem(market_pairs[i], empty_order, empty_order, "ORDERS REMOING ERROR: " # U.getErrorMessage(err));
        };
      };

      i := i + 1;
    };
  };

  func getCredits() : async* (AssocList.AssocList<Principal, Nat>) {
    /// here will be logic for calculating available credits for each pair
    /// based on the current state of the auction, quote credit limit and already placed orders
    /// temporary just simple return quote token credits divided by pairs count
    let size = market_pairs.size();
    let quote_token : Principal = await* auction.getQuoteToken();
    let token_credits : AssocList.AssocList<Principal, Nat> = await* auction.getCredits();
    let quote_token_credits : Nat = U.getByKeyOrTrap<Principal, Nat>(token_credits, quote_token, Principal.equal, "Error get quote token credits") / size;
    return AssocList.replace<Principal, Nat>(token_credits, quote_token, Principal.equal, ?quote_token_credits).0;
  };

  public func getPairsList() : async ([MarketMaker.MarketPair]) {
    let size = market_pairs.size();
    let token_credits = await* getCredits();
    Array.tabulate<MarketMaker.MarketPair>(
      size,
      func(i: Nat) : MarketMaker.MarketPair = getMarketPair(market_pairs[i].base_principal, market_pairs[i].quote_principal, token_credits),
    );
  };

  public func getHistory() : async ([HistoryModule.HistoryItemType]) {
    let size = history.size();
    Array.tabulate<HistoryModule.HistoryItemType>(
      size,
      func(i: Nat) : HistoryModule.HistoryItemType = history[i].getItem()
    );
  };

  public func startBot() : async (BotState) {
    Debug.print("Start bot");
    await* setBotState(true);
  };

  public func stopBot() : async (BotState) {
    Debug.print("Stop bot");
    await* cancelAllOrders();
    await* setBotState(false);
  };

  public func getBotState() : async (BotState) {
    {
      running = is_running;
    };
  };

  public func executeMarketMaking() : async () {
    var i : Nat = 0;
    let empty_order : MarketMakerModule.OrderInfo = {
      amount = 0;
      price = 0.0;
    };
    let size = market_pairs.size();
    let token_credits = await* getCredits();

    while (i < size) {
      let market_pair = getMarketPair(market_pairs[i].base_principal, market_pairs[i].quote_principal, token_credits);

      if (market_pair.base_credits == 0 or market_pair.quote_credits == 0) {
        if (market_pair.base_credits == 0) {
          addHistoryItem(market_pair, empty_order, empty_order, "Error processing pair: empty credits for " # Principal.toText(market_pair.base_principal));
        };
        if (market_pair.quote_credits == 0) {
          addHistoryItem(market_pair, empty_order, empty_order, "Error processing pair: empty credits for " # Principal.toText(market_pair.quote_principal));
        };
      } else {
        let execute_result = await* MarketMaker.execute(market_pair, oracle, auction);

        switch (execute_result) {
          case (#Ok(bid_order, ask_order)) {
            addHistoryItem(market_pair, bid_order, ask_order, "OK");
          };
          case (#Err(err)) {
            addHistoryItem(market_pair, empty_order, empty_order, U.getErrorMessage(err));
          };
        };
      };

      i := i + 1
    };
  };

  // TODO remove this later, just for Debug/tesging purposes
  public func addCredits() : async () {
    ignore await auction.getAuction().icrc84_notify({ token = Principal.fromText("5s5uw-viaaa-aaaaa-aaaaa-aaaaa-aaaaa-aa")});
    ignore await auction.getAuction().icrc84_notify({ token = Principal.fromText("to6hx-qyaaa-aaaaa-aaaaa-aaaaa-aaaaa-ab")});
    ignore await auction.getAuction().icrc84_notify({ token = Principal.fromText("ak2su-6iaaa-aaaaa-aaaaa-aaaaa-aaaaa-ac")});
  };

  func executeBot() : async () {
    if (is_running == false) {
      return;
    };

    // TODO remove this later, just for Debug/tesging purposes
    // await addCredits();

    await executeMarketMaking();
  };

  // TODO change timer value, 5 seconds just for Debug/tesging purposes
  Timer.recurringTimer<system>(#seconds (5), executeBot);
}
