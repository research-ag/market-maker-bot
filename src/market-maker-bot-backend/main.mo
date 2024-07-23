import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";
import Int64 "mo:base/Int64";
import Oracle "./oracle";

actor MarketMakerBot {
  var currentBid: ?(Float, Text) = null;
  var currentAsk: ?(Float, Text) = null;
  let spread: Float = 0.05;

  let oracleCanisterId: Text = "uf6dk-hyaaa-aaaaq-qaaaq-cai"; // Oracle canister ID

  public func getCurrentPrice() : async Nat64 {
    let oracle = actor (oracleCanisterId) : Oracle.Self;
    let request: Oracle.GetExchangeRateRequest = {
      timestamp = null;
      quote_asset = { class_ = #Cryptocurrency; symbol = "ICP" };
      base_asset = { class_ = #FiatCurrency; symbol = "USD" };
    };
    let response = await oracle.get_exchange_rate(request);

    switch (response) {
      case (#Ok(success)) {
        Debug.print("Current Price: " # Nat64.toText(success.rate));
        return success.rate;
      };
      case (#Err(error)) {
        Debug.print("Error: " # debug_show(error));
        throw Error.reject("Error getting exchange rate");
      };
    }
  };

  public func cancelPreviousOrders() : async () {
    if (Option.isSome(currentBid)) {
      let (_, bidId) = Option.unwrap(currentBid);
      Debug.print("Cancel current bid: " # bidId);
    };
    if (Option.isSome(currentAsk)) {
      let (_, askId) = Option.unwrap(currentAsk);
      Debug.print("Cancel current ask: " # askId);
    };
  };

  public func placeNewOrders(currentPrice: Nat64) : async () {
    let floatPrice = Float.fromInt64(Int64.fromNat64(currentPrice));
    let bidPrice = floatPrice * (1.0 - spread);
    let askPrice = floatPrice * (1.0 + spread);

    // let bidId = await (auctionCanisterId # "placeBid")(bidPrice);
    // let askId = await (auctionCanisterId # "placeAsk")(askPrice);

    Debug.print("New bid placed: " # Float.toText(bidPrice));
    Debug.print("New ask placed: " # Float.toText(askPrice));
  };

  func executeMarketMaking() : async () {
    Debug.print("execute...");
    let currentPrice = await getCurrentPrice();
    await cancelPreviousOrders();
    await placeNewOrders(currentPrice);
  };

  Timer.recurringTimer<system>(#seconds (5 * 60 * 1000), executeMarketMaking);
}
