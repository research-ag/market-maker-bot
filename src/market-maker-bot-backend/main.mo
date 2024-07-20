import Array "mo:base/Array";
import Float "mo:base/Float";
import Timer "mo:base/Timer";
import Debug "mo:base/Debug";

actor MarketMakerBot {
  var funds: Float = 1000.0;
  let spread: Float = 0.05;

  public func getCurrentPrice() : async Float {
    // TODO get the current price from the auction canister
    return 100.0;
  };

  public func calculateBidAsk(currentPrice: Float) : async (Float, Float) {
    let bid = currentPrice * (1.0 - spread);
    let ask = currentPrice * (1.0 + spread);
    return (bid, ask);
  };

  public func placeBidAsk(bid: Float, ask: Float) : async () {
    // TODO place bid ask to the auction canister
    Debug.print("Placing bid: " # Float.toText(bid));
    Debug.print("Placing ask: " # Float.toText(ask));
    funds := funds - bid;
    funds := funds - ask;
  };

  public func executeMarketMaking() : async () {
    let currentPrice = await getCurrentPrice();
    let (bid, ask) = await calculateBidAsk(currentPrice);
    await placeBidAsk(bid, ask);
  };

  Timer.recurringTimer(#seconds (60), async () {
    executeMarketMaking();
  });

  public func deposit(amount: Float) : async () {
    funds := funds + amount;
    Debug.print("Deposited: " # Float.toText(amount));
    Debug.print("New balance: " # Float.toText(funds));
  };

  public func withdraw(amount: Float) : async () {
    if (amount > funds) {
      Debug.print("Insufficient funds for withdrawal");
    } else {
      funds := funds - amount;
      Debug.print("Withdrew: " # Float.toText(amount));
      Debug.print("New balance: " # Float.toText(funds));
    }
  };

  public func checkBalance() : async Float {
    Debug.print("Current balance: " # Float.toText(funds));
    return funds;
  };
};