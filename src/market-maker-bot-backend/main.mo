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

actor MarketMakerBot {
  public type AssetData = {
    principal : Text;
    symbol : Text;
    decimals : Nat32;
  };

  public type BotState = {
    running : Bool;
  };

  public type AssetInfoWithCredits = {
    principal : Principal;
    symbol : Text;
    decimals : Nat32;
    credits : Nat;
  };

  public type MarketPairWithCredits = {
    base : AssetInfoWithCredits;
    quote : AssetInfoWithCredits;
    spread_value: Float;
  };

  let default_pair : MarketMakerModule.MarketPair = {
    quote = {
      principal = Principal.fromText("avqkn-guaaa-aaaaa-qaaea-cai"); // TKN_0
      asset = { class_ = #Cryptocurrency; symbol = "MCK_2" };
      decimals = 3;
    };
    base = {
      principal = Principal.fromText("by6od-j4aaa-aaaaa-qaadq-cai"); // TKN_4
      asset = { class_ = #Cryptocurrency; symbol = "MCK_1" };
      decimals = 3;
    };
    spread_value = 0.05;
  };

  var credits_map : HashMap.HashMap<Principal, Nat> = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);

  let auction : Auction.Self = actor "br5f7-7uaaa-aaaaa-qaaca-cai";
  // let auction : Auction.Self = actor "2qfpd-kyaaa-aaaao-a3pka-cai";
  let oracle : Oracle.Self = actor "a4tbr-q4aaa-aaaaa-qaafq-cai";
  // let oracle : Oracle.Self = actor "uf6dk-hyaaa-aaaaq-qaaaq-cai";

  var market_makers : [MarketMakerModule.MarketMaker] = [MarketMakerModule.MarketMaker(default_pair, oracle, auction)];
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

  func addHistoryItem(pair : MarketMakerModule.MarketPair, bidOrder : MarketMakerModule.OrderInfo, askOrder : MarketMakerModule.OrderInfo, message : Text) : () {
    let historyItem = HistoryModule.HistoryItem(pair, bidOrder, askOrder, message);
    history := Array.append(
      history,
      [historyItem],
    );
    Debug.print(historyItem.getItem());
  };

  func getCreditsByToken(token : Principal) : (Nat) {
    let _credits : ?Nat = credits_map.get(token);
    switch (_credits) {
      case (?_credits) _credits;
      case (null) 0;
    }
  };

  func queryCredits() : async* () {
    let credits : [(Principal, Auction.CreditInfo)] = await auction.queryCredits();

    credits_map := HashMap.HashMap<Principal, Nat>(credits.size(), Principal.equal, Principal.hash);

    for (credit in credits.vals()) {
      credits_map.put(credit.0, credit.1.total);
    };
  };

  func setBotState(running : Bool) : async* (BotState) {
    is_running := running;

    {
      running = is_running;
    };
  };

  public func addPair(base_asset_data : AssetData, quote_asset_data : AssetData, spread_value : Float) : async (Nat) {
    let base_asset_info : MarketMakerModule.AssetInfo = getAssetInfo(base_asset_data);
    let quote_asset_info : MarketMakerModule.AssetInfo = getAssetInfo(quote_asset_data);
    let market_pair : MarketMakerModule.MarketPair = getMarketPair(base_asset_info, quote_asset_info, spread_value);
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

  public func getPairsList() : async ([MarketPairWithCredits]) {
    let size = market_makers.size();

    await* queryCredits();

    Array.tabulate<MarketPairWithCredits>(
      size,
      func(i: Nat) : MarketPairWithCredits {
        let pair = market_makers[i].getPair();

        {
          base = {
            principal = pair.base.principal;
            symbol = pair.base.asset.symbol;
            decimals = pair.base.decimals;
            credits = getCreditsByToken(pair.base.principal);
          };
          quote = {
            principal = pair.quote.principal;
            symbol = pair.quote.asset.symbol;
            decimals = pair.quote.decimals;
            credits = getCreditsByToken(pair.quote.principal);
          };
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

  public func getHistory() : async ([Text]) {
    let size = history.size();
    Array.tabulate<Text>(
      size,
      func(i: Nat) : Text = history[i].getItem()
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

    await* queryCredits();

    while (i < market_makers.size()) {
      let market_maker : MarketMakerModule.MarketMaker = market_makers[i];
      let pair : MarketMakerModule.MarketPair = market_maker.getPair();

      try {
        let base_credit = getCreditsByToken(pair.base.principal);
        if (base_credit == 0) {
          throw Error.reject("Empty credits for " # Principal.toText(pair.base.principal));
        };

        let quote_credit = getCreditsByToken(pair.quote.principal);
        if (quote_credit == 0) {
          throw Error.reject("Empty credits for " # Principal.toText(pair.quote.principal));
        };

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
      } catch (e) {
        addHistoryItem(pair, empty_order, empty_order, "Error processing pair: " # Error.message(e));
      };

      i := i + 1;
    }
  };

  func executeBot() : async () {
    if (is_running == false) {
      return;
    };

    await executeMarketMaking();
  };

  Timer.recurringTimer<system>(#seconds (5), executeBot);
}
