import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Nat32 "mo:base/Nat32";
import Cycles "mo:base/ExperimentalCycles";
import Oracle "./oracle";
import Auction "./auction";

actor MarketMakerBot {
  type CurrencyRate = {
    rate : Nat64;
    decimals : Nat32;
  };

  type CreditsInfo = {
    baseCredit : Nat;
    quoteCredit : Nat;
  };

  type PricesInfo = {
    bidPrice : Float;
    askPrice : Float;
  };

  type ValumesInfo = {
    bidVolume : Nat;
    askVolume : Nat;
  };

  public type AssetInfo = {
    principal : Principal;
    asset : Oracle.Asset;
    decimals : Nat32;
  };

  public type OrderInfo = {
    token : Principal;
    amount : Nat;
    price : Float;
  };

  var spreadValue: Float = 0.05; // 5 percent

  let auction : Auction.Self = actor "2qfpd-kyaaa-aaaao-a3pka-cai";
  let oracle : Oracle.Self = actor "yoizw-hyaaa-aaaab-qacea-cai";
  // let oracle : Oracle.Self = actor "uf6dk-hyaaa-aaaaq-qaaaq-cai";

  let quote : AssetInfo = {
    principal = Principal.fromText("5s5uw-viaaa-aaaaa-aaaaa-aaaaa-aaaaa-aa"); // TKN_0
    asset = { class_ = #Cryptocurrency; symbol = "USDC"};
    decimals = 3;
  };
  let base : AssetInfo = {
    principal = Principal.fromText("5pli6-taaaa-aaaaa-aaaaa-aaaaa-aaaaa-ae"); // TKN_4
    asset = { class_ = #Cryptocurrency; symbol = "ICP"};
    decimals = 3;
  };

  public func getSpreadPercent() : async (Nat) {
    Int.abs(Float.toInt(spreadValue * 100));
  };

  public func setSpreadPercent(value : Nat) : async (Float) {
    spreadValue := Float.fromInt(value) / 100;
    spreadValue;
  };

  public func getCurrentRate(base: Oracle.Asset, quote: Oracle.Asset) : async CurrencyRate {
    let request: Oracle.GetExchangeRateRequest = {
      timestamp = null;
      quote_asset = quote;
      base_asset = base;
    };
    Cycles.add<system>(10_000_000_000);
    let response = await oracle.get_exchange_rate(request);

    switch (response) {
      case (#Ok(success)) {
        let currencyRate : CurrencyRate = {
          rate = success.rate;
          decimals = success.metadata.decimals;
        };

        return currencyRate;
      };
      case (#Err(_)) {
        throw Error.reject("Error get rates");
      };
    }
  };

  public func getPrices(spread : Float, currencyRate : CurrencyRate) : async PricesInfo {
    let exponent : Float = Float.fromInt64(Int64.fromNat64(Nat32.toNat64(currencyRate.decimals)));
    let floatPrice : Float = Float.fromInt64(Int64.fromNat64(currencyRate.rate)) / Float.pow(Float.fromInt(10), exponent);
    let bidPrice = floatPrice * (1.0 - spread);
    let askPrice = floatPrice * (1.0 + spread);

    {
      bidPrice = bidPrice;
      askPrice = askPrice;
    }
  };

  public func getVolumes(credits : CreditsInfo, prices : PricesInfo) : async ValumesInfo {
    {
      bidVolume = Int.abs(Float.toInt(Float.fromInt(credits.quoteCredit) / prices.bidPrice));
      askVolume = credits.baseCredit;
    }
  };

  public func queryCredits(base : Principal, quote : Principal) : async CreditsInfo {
    let credits : [(Principal, Auction.CreditInfo)] = await auction.queryCredits();
    var baseCredit : Nat = 0;
    var quoteCredit : Nat = 0;

    for (credit in credits.vals()) {
      if (credit.0 == base) {
        baseCredit := credit.1.total;
      } else if (credit.0 == quote) {
        quoteCredit := credit.1.total;
      }
    };

    {
      baseCredit = baseCredit;
      quoteCredit = quoteCredit;
    }
  };

  func replaceOrders(bid : OrderInfo, ask : OrderInfo) : async* [Nat] {
    let response = await auction.manageOrders(
      ?(#all (?[bid.token, ask.token])), // cancell all orders for tokens
      [#bid (bid.token, bid.amount, bid.price), #ask (ask.token, ask.amount, ask.price)],
    );

    switch (response) {
      case (#Ok(success)) {
        return success;
      };
      case (#Err(_)) {
        throw Error.reject("Error placing orders");
      };
    }
  };

  public func marketMaking() : async [Nat] {
    let { baseCredit; quoteCredit } = await queryCredits(base.principal, quote.principal);
    let currentRate : CurrencyRate = await getCurrentRate(base.asset, quote.asset);
    let { bidPrice; askPrice } = await getPrices(spreadValue, currentRate);
    let { bidVolume; askVolume } = await getVolumes({ baseCredit; quoteCredit }, { bidPrice; askPrice });

    let bidOrder : OrderInfo = {
      token = base.principal;
      amount = bidVolume;
      price = bidPrice;
    };
    let askOrder : OrderInfo = {
      token = base.principal;
      amount = askVolume;
      price = askPrice;
    };

    let orders = await* replaceOrders(bidOrder, askOrder);

    orders;
  };

  func executeMarketMaking() : async () {
    ignore await marketMaking();
  };

  Timer.recurringTimer<system>(#seconds (5 * 60 * 1000), executeMarketMaking);
}
