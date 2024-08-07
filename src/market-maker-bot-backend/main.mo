import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Nat32 "mo:base/Nat32";
import Debug "mo:base/Debug";
import MarketMakerModule "./market_maker";
import HistoryModule "./history";

actor MarketMakerBot {
  public type AssetData = {
    principal : Text;
    symbol : Text;
    decimals : Nat32;
  };

  let default_pair : MarketMakerModule.MarketPair = {
    quote = {
      principal = Principal.fromText("5s5uw-viaaa-aaaaa-aaaaa-aaaaa-aaaaa-aa"); // TKN_0
      asset = { class_ = #Cryptocurrency; symbol = "USDC" };
      decimals = 3;
    };
    base = {
      principal = Principal.fromText("5pli6-taaaa-aaaaa-aaaaa-aaaaa-aaaaa-ae"); // TKN_4
      asset = { class_ = #Cryptocurrency; symbol = "ICP" };
      decimals = 3;
    };
    spread_value = 0.05;
  };

  var market_makers : [MarketMakerModule.MarketMaker] = [MarketMakerModule.MarketMaker(default_pair)];
  var history : [HistoryModule.HistoryItem] = [];

  func shareData() : ([MarketMakerModule.MarketPair]) {
    Array.tabulate(
      market_makers.size(),
      func(i: Nat) : MarketMakerModule.MarketPair = market_makers[i].getPair()
    );
  };

  func unshareData(arr : [MarketMakerModule.MarketPair]) : () {
    market_makers := Array.tabulate(
      arr.size(),
      func(i: Nat) : MarketMakerModule.MarketMaker = MarketMakerModule.MarketMaker(arr[i])
    );
  };

  system func preupgrade() {
    market_makers_data := shareData();
    Debug.print("Preupgrade" # debug_show(market_makers_data));
  };

  system func postupgrade() {
    Debug.print("Postupgrade" # debug_show(market_makers_data));
    unshareData(market_makers_data);
  };

  stable var market_makers_data : [MarketMakerModule.MarketPair] = shareData();

  func getAssetInfo(asset_data : AssetData) : (MarketMakerModule.AssetInfo) {
    {
      principal = Principal.fromText(asset_data.principal);
      asset = { class_ = #Cryptocurrency; symbol = asset_data.symbol };
      decimals = asset_data.decimals;
    };
  };

  func getMarketPair(base_asset_info : MarketMakerModule.AssetInfo, quote_asset_info : MarketMakerModule.AssetInfo, spread_value : Float) : (MarketMakerModule.MarketPair) {
    {
      base = base_asset_info;
      quote = quote_asset_info;
      spread_value = spread_value;
    }
  };

  func getErrorMessage(error : MarketMakerModule.ExecutionError) : Text {
    switch (error) {
      case (#PlacementError) "Placement order error";
      case (#CancellationError) "Cancellation order error";
      case (#UnknownPrincipal) "Unknown principal error";
      case (#RatesError) "No rates error";
      case (#ConflictOrderError) "Conflict order error";
      case (#UnknownAssetError) "Unknown asset error";
      case (#NoCreditError) "No credit error";
      case (#TooLowOrderError) "Too low order error";
    }
  };

  public func addPair(base_asset_data : AssetData, quote_asset_data : AssetData, spread_value : Float) : async (Nat) {
    let base_asset_info : MarketMakerModule.AssetInfo = getAssetInfo(base_asset_data);
    let quote_asset_info : MarketMakerModule.AssetInfo = getAssetInfo(quote_asset_data);
    let market_pair : MarketMakerModule.MarketPair = getMarketPair(base_asset_info, quote_asset_info, spread_value);
    let market_maker : MarketMakerModule.MarketMaker = MarketMakerModule.MarketMaker(market_pair);
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

  public func getPairsList() : async ([MarketMakerModule.MarketPair]) {
    let size = market_makers.size();

    Array.tabulate<MarketMakerModule.MarketPair>(
      size,
      func(i: Nat) : MarketMakerModule.MarketPair = market_makers[i].getPair()
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

    ignore await market_pair_to_remove.removeOrders();

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

  public func getHistory() : async ([Text]) {
    let size = history.size();
    Array.tabulate<Text>(
      size,
      func(i: Nat) : Text = history[i].getItem()
    );
  };

  func executeMarketMaking() : async () {
    var i : Nat = 0;
    while (i < market_makers.size()) {
      let market_maker : MarketMakerModule.MarketMaker = market_makers[i];
      let execute_result = await market_maker.execute();

      switch (execute_result) {
        case (#Ok(bid_order, ask_order)) {
          let historyItem = HistoryModule.HistoryItem(market_maker.getPair(), bid_order, ask_order, "OK");
          history := Array.append(
            history,
            [historyItem],
          );
          Debug.print(historyItem.getItem());
        };
        case (#Err(err)) {
          let empty_order : MarketMakerModule.OrderInfo = {
            amount = 0;
            price = 0.0;
          };
          let historyItem = HistoryModule.HistoryItem(market_maker.getPair(), empty_order, empty_order, getErrorMessage(err));
          history := Array.append(
            history,
            [historyItem],
          );
          Debug.print(historyItem.getItem());
        };
      };

      i := i + 1;
    }
  };

  Timer.recurringTimer<system>(#seconds (5), executeMarketMaking);
}
