/// A module which contain implementation of market maker orchestrationg
/// Contain all public methods for bot which helps to manage bot state
/// Manage list of trading pairs, have only one fixed quote asset for all pairs
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Bool "mo:base/Bool";
import Oracle "./oracle";
import Auction "./auction";
import MarketMakerModule "./market_maker";
import HistoryModule "./history";

actor class MarketMakerBot(auction_principal: Principal, oracle_principal: Principal, quote_asset_principal: Principal, quote_asset_decimal: Nat32, quote_asset_symbol: Text) = self {
  public type BotState = {
    running : Bool;
  };

  public type PairInfo = {
    base_asset : MarketMakerModule.AssetInfo;
    base_credits : Nat;
    quote_asset : MarketMakerModule.AssetInfo;
    quote_credits : Nat;
    spread_value: Float;
  };

  let quote_asset : MarketMakerModule.AssetInfo = {
    principal = quote_asset_principal;
    asset = {
      class_ = #Cryptocurrency;
      symbol = quote_asset_symbol;
    };
    decimals = quote_asset_decimal;
  };

  var credits_map : HashMap.HashMap<Principal, Nat> = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);

  let auction : Auction.Self = actor (Principal.toText(auction_principal));
  let oracle : Oracle.Self = actor (Principal.toText(oracle_principal));

  var market_makers : [MarketMakerModule.MarketMaker] = [];
  var history : [HistoryModule.HistoryItem] = [];
  var is_running : Bool = false;

  func shareData() : ([MarketMakerModule.MarketPair]) {
    Array.tabulate(
      market_makers.size(),
      func(i: Nat) : MarketMakerModule.MarketPair = market_makers[i].getPair()
    );
  };

  func unshareData(arr : [MarketMakerModule.MarketPair]) : () {
    market_makers := Array.tabulate(
      arr.size(),
      func(i: Nat) : MarketMakerModule.MarketMaker = MarketMakerModule.MarketMaker(arr[i], oracle, auction)
    );
  };

  system func preupgrade() {
    market_makers_data := shareData();
    bot_running_state := is_running;
    Debug.print("Preupgrade" # debug_show(market_makers_data));
  };

  system func postupgrade() {
    Debug.print("Postupgrade" # debug_show(market_makers_data));
    unshareData(market_makers_data);
    is_running := bot_running_state;
  };

  stable var bot_running_state : Bool = is_running;
  stable var market_makers_data : [MarketMakerModule.MarketPair] = shareData();

  func getErrorMessage(error : MarketMakerModule.ExecutionError) : Text {
    switch (error) {
      case (#PlacementError) "Placement order error";
      case (#CancellationError) "Cancellation order error";
      case (#UnknownPrincipal) "Unknown principal error";
      case (#UnknownError) "Unknown error";
      case (#RatesError) "No rates error";
      case (#ConflictOrderError) "Conflict order error";
      case (#UnknownAssetError) "Unknown asset error";
      case (#NoCreditError) "No credit error";
      case (#TooLowOrderError) "Too low order error";
    }
  };

  func addHistoryItem(pair : MarketMakerModule.MarketPair, bidOrder : MarketMakerModule.OrderInfo, askOrder : MarketMakerModule.OrderInfo, message : Text) : () {
    let historyItem = HistoryModule.HistoryItem(pair, bidOrder, askOrder, message);
    history := Array.append(
      history,
      [historyItem],
    );
    Debug.print(historyItem.getText());
  };

  func getCreditsByToken(token : Principal) : (Nat) {
    let _credits : ?Nat = credits_map.get(token);
    switch (_credits) {
      case (?_credits) _credits;
      case (null) 0;
    }
  };

  func queryCredits() : async* () {
    try {
      let credits : [(Principal, Auction.CreditInfo)] = await auction.queryCredits();

      Debug.print("Credits " # debug_show(credits));

      credits_map := HashMap.HashMap<Principal, Nat>(credits.size(), Principal.equal, Principal.hash);

      for (credit in credits.vals()) {
        credits_map.put(credit.0, credit.1.total);
      };

    } catch (e) {
      Debug.print(Error.message(e));
    }
  };

  func setBotState(running : Bool) : async* (BotState) {
    is_running := running;

    {
      running = is_running;
    };
  };

  public func addPair(params : { principal : Text; symbol : Text; decimals : Nat32; spread_value : Float }) : async (Nat) {
    let base_asset : MarketMakerModule.AssetInfo = {
      principal = Principal.fromText(params.principal); // TKN_0
      asset = {
        class_ = #Cryptocurrency;
        symbol = params.symbol;
      };
      decimals = params.decimals;
    };
    let market_pair : MarketMakerModule.MarketPair = {
      base = base_asset;
      quote = quote_asset;
      spread_value = params.spread_value;
    };
    let market_maker : MarketMakerModule.MarketMaker = MarketMakerModule.MarketMaker(market_pair, oracle, auction);
    let size = market_makers.size();

    market_makers := Array.tabulate(
      size + 1,
      func(i: Nat) : MarketMakerModule.MarketMaker {
        if (i < size) {
          return market_makers[i];
        } else {
          return market_maker;
        }
      }
    );

    market_makers.size();
  };

  public func getPairsList() : async ([PairInfo]) {
    let size = market_makers.size();
    Debug.print("Market pairs count: " # debug_show(size));

    await* queryCredits();

    Array.tabulate<PairInfo>(
      size,
      func(i: Nat) : PairInfo {
        let pair = market_makers[i].getPair();

        {
          base_asset = pair.base;
          base_credits = getCreditsByToken(pair.base.principal);
          quote_asset = pair.base;
          quote_credits = getCreditsByToken(pair.quote.principal);
          spread_value = pair.spread_value;
        };
      }
    );
  };

  public func removePairByIndex(idx : Nat) : async {
    #Ok : Nat;
    #Err : {
      #CancellationError;
    };
  } {
    let size = market_makers.size();
    let market_pair_to_remove : MarketMakerModule.MarketMaker = market_makers[idx];

    ignore await* market_pair_to_remove.removeOrders();

    if (idx >= size) {
      return #Ok(market_makers.size());
    };

    if (idx == 0) {
      market_makers := Array.tabulate(
        size - 1,
        func(i: Nat) : MarketMakerModule.MarketMaker = market_makers[i + 1]
      );
    } else {
      let begin : [MarketMakerModule.MarketMaker] = Array.tabulate(
        idx,
        func(i: Nat) : MarketMakerModule.MarketMaker = market_makers[i]
      );
      let end : [MarketMakerModule.MarketMaker] = Array.tabulate(
        size - idx - 1,
        func(i: Nat) : MarketMakerModule.MarketMaker = market_makers[idx + i + 1]
      );
      market_makers := Array.append<MarketMakerModule.MarketMaker>(begin, end);
    };

    return #Ok(market_makers.size());
  };

  public func getHistory() : async ([HistoryModule.HistoryItemType]) {
    let size = history.size();
    Array.tabulate<HistoryModule.HistoryItemType>(
      size,
      func(i: Nat) : HistoryModule.HistoryItemType = history[i].getItem()
    );
  };

  public func startBot() : async (BotState) {
    Debug.print("Start auto trading");
    await* setBotState(true);
  };

  public func stopBot() : async (BotState) {
    Debug.print("Stop auto trading");
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
    let size = market_makers.size();

    await* queryCredits();

    while (i < size) {
      let market_maker : MarketMakerModule.MarketMaker = market_makers[i];
      let pair : MarketMakerModule.MarketPair = market_maker.getPair();

      try {
        let base_credit = getCreditsByToken(pair.base.principal);
        // Here we divide whole quote asset credit by count of pairs to place orders for all pairs
        let quote_credit = getCreditsByToken(pair.quote.principal) / size;
        if (base_credit == 0 or quote_credit == 0) {
          if (base_credit == 0) {
            addHistoryItem(pair, empty_order, empty_order, "Error processing pair: no credits for " # Principal.toText(pair.base.principal));
          };
          if (quote_credit == 0) {
            addHistoryItem(pair, empty_order, empty_order, "Error processing pair: no credits for " # Principal.toText(pair.quote.principal));
          };
        } else {
          let credits : MarketMakerModule.CreditsInfo = {
            base_credit = base_credit;
            quote_credit = quote_credit;
          };
          let execute_result = await* market_maker.execute(credits);

          switch (execute_result) {
            case (#Ok(bid_order, ask_order)) {
              addHistoryItem(pair, bid_order, ask_order, "OK");
            };
            case (#Err(err)) {
              addHistoryItem(pair, empty_order, empty_order, getErrorMessage(err));
            };
          };
        }

      } catch (e) {
        addHistoryItem(pair, empty_order, empty_order, "Error processing pair: " # Error.message(e));
      };

      i := i + 1;
    }
  };

  // TODO remove this later, just for Debug/tesging purposes
  public func addCredits() : async () {
    ignore await auction.icrc84_notify({ token = Principal.fromText("5s5uw-viaaa-aaaaa-aaaaa-aaaaa-aaaaa-aa")});
    ignore await auction.icrc84_notify({ token = Principal.fromText("to6hx-qyaaa-aaaaa-aaaaa-aaaaa-aaaaa-ab")});
    ignore await auction.icrc84_notify({ token = Principal.fromText("owzbv-3yaaa-aaaaa-aaaaa-aaaaa-aaaaa-ad")});
    ignore await auction.icrc84_notify({ token = Principal.fromText("ak2su-6iaaa-aaaaa-aaaaa-aaaaa-aaaaa-ac")});
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
