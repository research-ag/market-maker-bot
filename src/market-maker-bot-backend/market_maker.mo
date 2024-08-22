import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Nat32 "mo:base/Nat32";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Oracle "./oracle";
import Auction "./auction";

module MarketMakerModule {
  type CurrencyRate = {
    rate : Nat64;
    decimals : Nat32;
  };

  type PricesInfo = {
    bid_price : Float;
    ask_price : Float;
  };

  type ValumesInfo = {
    bid_volume : Nat;
    ask_volume : Nat;
  };

  public type CreditsInfo = {
    base_credit : Nat;
    quote_credit : Nat;
  };

  public type OrderInfo = {
    amount : Nat;
    price : Float;
  };

  public type AssetInfo = {
    principal : Principal;
    asset : Oracle.Asset;
    decimals : Nat32;
  };

  public type MarketPair = {
    base : AssetInfo;
    quote : AssetInfo;
    spread_value : Float;
  };

  public type ExecutionError = {
    #PlacementError;
    #CancellationError;
    #UnknownPrincipal;
    #RatesError;
    #ConflictOrderError;
    #UnknownAssetError;
    #NoCreditError;
    #TooLowOrderError;
  };

  // Consider making a class Oracle which
  // - takes xrc as constructor argument
  // - provides function getCurrenrRate(base, quote)
  // - is instantiated once in main.mo
  // - is passed to the MarketMaker constructor in place of xrc : Oracle.Self
  // So essentially a class that wraps around Oracle.Self
  //
  // As a side effect: This helps in testing MarketMaker with Motoko-only tests (with the interpreter, mops test)
  // The test can mock the class without actually using Oracle.Self
  func getCurrentRate(xrc : Oracle.Self, base : Oracle.Asset, quote : Oracle.Asset) : async* {
    #Ok : CurrencyRate;
    #Err : {
      #ErrorGetRates;
    };
  } {
    let request : Oracle.GetExchangeRateRequest = {
      timestamp = null;
      quote_asset = quote;
      base_asset = base;
    };
    Debug.print("EXECUTE getCurrentRate requets" # debug_show(request));
    Cycles.add<system>(10_000_000_000);
    let response = await xrc.get_exchange_rate(request);
    Debug.print("EXECUTE getCurrentRate response" # debug_show(response));

    switch (response) {
      case (#Ok(success)) {
        Debug.print("EXECUTE getCurrentRate success" # debug_show(success));
        let currency_rate : CurrencyRate = {
          rate = success.rate;
          decimals = success.metadata.decimals;
        };

        Debug.print("EXECUTE getCurrentRate currency_rate" # debug_show(currency_rate));
        return #Ok(currency_rate);
      };
      case (#Err(_)) {
        return #Err(#ErrorGetRates);
      };
    };
  };

  // Consider making a class Auction which
  // - takes ac as constructor argument
  // - provides function replaceOrders
  // - is instantiated once in main.mo
  // - is passed to the MarketMaker constructor in place of ac : Auction.Self
  // So essentially a class that wraps around Auction.Self
  //
  // As a side effect: This helps in testing MarketMaker with Motoko-only tests (with the interpreter, mops test)
  // The test can mock the class without actually using Auction.Self
  func replaceOrders(ac : Auction.Self, token : Principal, bid : OrderInfo, ask : OrderInfo) : async* {
    #Ok : [Nat];
    #Err : Auction.ManageOrdersError;
  } {
    Debug.print("EXECUTE replaceOrders" # debug_show({ token; bid; ask; }));
    try {

      let response = await ac.manageOrders(
        ?(#all(?[token])), // cancell all orders for tokens
        [#bid(token, bid.amount, bid.price), #ask(token, ask.amount, ask.price)],
      );

      Debug.print("EXECUTE response" # debug_show(response));
      switch (response) {
        case (#Ok(success)) #Ok(success);
        case (#Err(error)) {
          Debug.print("EXECUTE response error" # debug_show(error));
          switch (error) {
            case (#cancellation(_)) {
              let response = await ac.manageOrders(
                ?(#orders([])),
                [#bid(token, bid.amount, bid.price), #ask(token, ask.amount, ask.price)],
              );

              switch (response) {
                case (#Ok(success)) #Ok(success);
                case (#Err(error)) #Err(error);
              };
            };
            case (_) #Err(error);
          };
        };
      };
    } catch (e) {
      Debug.print("EXECUTE replaceOrders ERROR" # Error.message(e));
      #Err(#UnknownPrincipal);
    }
  };

  let digits : Float = 5;

  func limitPrecision(x : Float) : Float {
    let e = - Float.log(x) / 2.302_585_092_994_045;
    let e1 = Float.floor(e) + digits;
    Float.floor(x * 10 ** e1) * 10 ** -e1;
  };

  func getPrices(spread : Float, currency_rate : CurrencyRate) : PricesInfo {
    let exponent : Float = Float.fromInt64(Int64.fromNat64(Nat32.toNat64(currency_rate.decimals)));
    let float_price : Float = Float.fromInt64(Int64.fromNat64(currency_rate.rate)) / Float.pow(10, exponent);

    {
      bid_price = limitPrecision(float_price * (1.0 - spread));
      ask_price = limitPrecision(float_price * (1.0 + spread));
    };
  };

  func calculateVolumeStep(price : Float) : Int {
    let p = price / Float.fromInt(10 ** 3);
    if (p >= 1) return 1;
    let zf = - Float.log(p) / 2.302_585_092_994_045;
    Int.abs(10 ** Float.toInt(zf));
  };

  func getVolumes(credits : CreditsInfo, prices : PricesInfo) : ValumesInfo {
    let volume_step = calculateVolumeStep(prices.bid_price);
    {
      bid_volume = Int.abs((Float.toInt(Float.fromInt(credits.quote_credit) / prices.bid_price) / volume_step) * volume_step);
      ask_volume = Int.abs((credits.base_credit / volume_step) * volume_step);
    }
  };

  public class MarketMaker(pair : MarketPair, xrc : Oracle.Self, ac : Auction.Self) {

    public func execute(credits : CreditsInfo) : async* {
      #Ok : (OrderInfo, OrderInfo);
      #Err : ExecutionError;
    } {
      // let { base_credit; quote_credit } = await* queryCredits(pair.base.principal, pair.quote.principal);
      Debug.print("EXECUTE " # debug_show(credits) # ", pair " #debug_show(pair));
      let { base_credit; quote_credit } = credits;
      let current_rate_result = await* getCurrentRate(xrc, pair.base.asset, pair.quote.asset);
      Debug.print("EXECUTE current_rate_result" # debug_show(current_rate_result));

      switch (current_rate_result) {
        case (#Ok(current_rate)) {
          let { bid_price; ask_price } = getPrices(pair.spread_value, current_rate);
          Debug.print("EXECUTE getPrices" # debug_show({ bid_price; ask_price }));
          let { bid_volume; ask_volume } = getVolumes({ base_credit; quote_credit }, { bid_price; ask_price });
          Debug.print("EXECUTE getVolumes" # debug_show({ bid_volume; ask_volume }));

          let bid_order : OrderInfo = {
            amount = bid_volume;
            price = bid_price;
          };
          Debug.print("EXECUTE bid_order" # debug_show(bid_order));
          let ask_order : OrderInfo = {
            amount = ask_volume;
            price = ask_price;
          };
          Debug.print("EXECUTE ask_order" # debug_show(ask_order));

          let replace_orders_result = await* replaceOrders(ac, pair.base.principal, bid_order, ask_order);
          Debug.print("EXECUTE replace_orders_result" # debug_show(replace_orders_result));

          switch (replace_orders_result) {
            case (#Ok(_)) #Ok(bid_order, ask_order);
            case (#Err(err)) {
              switch (err) {
                case (#placement(err)) {
                  switch (err.error) {
                    case (#ConflictingOrder(_)) #Err(#ConflictOrderError);
                    case (#UnknownAsset) #Err(#UnknownAssetError);
                    case (#NoCredit) #Err(#NoCreditError);
                    case (#TooLowOrder) #Err(#TooLowOrderError);
                  };
                };
                case (#cancellation(err)) #Err(#CancellationError);
                case (#UnknownPrincipal) #Err(#UnknownPrincipal);
              };
            };
          };
        };
        case (#Err(err)) {
          switch (err) {
            case (#ErrorGetRates) #Err(#RatesError);
          };
        };
      };
    };

    public func removeOrders() : async* {
      #Ok;
      #Err : {
        #CancellationError;
      };
    } {
      let response = await ac.manageOrders(
        ?(#all(?[pair.base.principal])), // cancell all orders for tokens
        [],
      );

      switch (response) {
        case (#Ok(_)) #Ok;
        case (#Err(_)) #Err(#CancellationError);
      };
    };

    public func getPair() : (MarketPair) {
      pair;
    };
  };
};
