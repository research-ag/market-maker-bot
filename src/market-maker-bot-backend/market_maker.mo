/// A module which contain implementation of market maker execution
/// Contain public execute function which is require pair information, oracle and auction wrapper instances
/// also contain all necessary types and functions to calculate prices and volumes
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Int32 "mo:base/Int32";

import Vec "mo:vector";

import OracleWrapper "./oracle_wrapper";
import AuctionWrapper "./auction_wrapper";
import U "./utils";

module MarketMaker {
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

  public type TokenDescription = {
    principal : Principal;
    symbol : Text;
    decimals : Nat32;
  };

  public type MarketPairShared = {
    base : TokenDescription;
    base_credits : Nat;
    quote_credits : Nat;
    spread_value : Float;
  };

  public type MarketPair = {
    base : TokenDescription;
    // total base token credits: available + locked by currently placed ask
    var base_credits : Nat;
    // total quote token credits assigned to this pair: available + locked by currently placed bid
    var quote_credits : Nat;
    var spread_value : Float;
  };

  let digits : Float = 5;

  func limitPrecision(x : Float) : Float {
    let e = - Float.log(x) / 2.302_585_092_994_045;
    let e1 = Float.floor(e) + digits;
    Float.floor(x * 10 ** e1) * 10 ** -e1;
  };

  public func sharePair(pair : MarketPair) : MarketPairShared {
    {
      pair with
      base_credits = pair.base_credits;
      quote_credits = pair.quote_credits;
      spread_value = pair.spread_value;
    };
  };

  public func getPrices(spread : Float, currency_rate : Float, decimals_multiplicator : Int32) : PricesInfo {
    // normalize the price before create the order to the smallest units of the tokens
    let multiplicator : Float = Float.fromInt64(Int32.toInt64(decimals_multiplicator));

    {
      bid_price = limitPrecision(currency_rate * (1.0 - spread) * Float.pow(10, multiplicator));
      ask_price = limitPrecision(currency_rate * (1.0 + spread) * Float.pow(10, multiplicator));
    };
  };

  func calculateVolumeStep(price : Float) : Nat {
    let p = price / Float.fromInt(10 ** 3);
    if (p >= 1) return 1;
    let zf = - Float.log(p) / 2.302_585_092_994_045;
    Int.abs(10 ** Float.toInt(zf));
  };

  func getVolumes(credits : CreditsInfo, prices : PricesInfo) : ValumesInfo {
    let volume_step = calculateVolumeStep(prices.bid_price);
    let truncToStep : Nat -> Nat = func(x) = x - x % volume_step;
    let bid_volume : Nat = Int.abs((Float.toInt(Float.fromInt(credits.quote_credit) / prices.bid_price)));
    {
      bid_volume = truncToStep(bid_volume);
      ask_volume = truncToStep(credits.base_credit);
    };
  };

  public func execute(
    quote : TokenDescription,
    pairs : [MarketPair],
    xrc : OracleWrapper.Self,
    ac : AuctionWrapper.Self,
    sessionNumber : Nat,
  ) : async* {
    #Ok : [(OrderInfo, OrderInfo, Float)];
    #Err : (U.ExecutionError, ?MarketPairShared, ?OrderInfo, ?OrderInfo, ?Float);
  } {
    let replaceArgs : Vec.Vector<(token : Principal, bid : OrderInfo, ask : OrderInfo)> = Vec.new();
    let rates : Vec.Vector<Float> = Vec.new();

    for (pair in pairs.vals()) {
      let ?current_rate = U.upperResultToOption(await* xrc.getExchangeRate(pair.base.symbol, quote.symbol)) else return #Err(#RatesError, null, null, null, null);

      // calculate multiplicator which help to normalize the price before create
      // the order to the smallest units of the tokens
      let price_decimals_multiplicator : Int32 = Int32.fromNat32(quote.decimals) - Int32.fromNat32(pair.base.decimals);

      let { bid_price; ask_price } = getPrices(pair.spread_value, current_rate, price_decimals_multiplicator);
      let { bid_volume; ask_volume } = getVolumes({ base_credit = pair.base_credits; quote_credit = pair.quote_credits }, { bid_price; ask_price });

      Vec.add(rates, current_rate);
      Vec.add(
        replaceArgs,
        (
          pair.base.principal,
          {
            amount = bid_volume;
            price = bid_price;
          },
          {
            amount = ask_volume;
            price = ask_price;
          },
        ),
      );
    };

    let replace_orders_result = await* ac.replaceOrders(Vec.toArray(replaceArgs), ?sessionNumber);

    switch (replace_orders_result) {
      case (#Ok _) {
        Array.tabulate<(OrderInfo, OrderInfo, Float)>(
          pairs.size(),
          func(i) = (Vec.get(replaceArgs, i).1, Vec.get(replaceArgs, i).2, Vec.get(rates, i)),
        ) |> #Ok(_);
      };
      case (#Err(err)) {
        switch (err) {
          case (#placement(err)) {
            let pair = sharePair(pairs[err.index]);
            let (_, bid_order, ask_order) = Vec.get(replaceArgs, err.index);
            let current_rate = Vec.get(rates, err.index);
            switch (err.error) {
              case (#ConflictingOrder(_)) #Err(#ConflictOrderError, ?pair, ?bid_order, ?ask_order, ?current_rate);
              case (#UnknownAsset) #Err(#UnknownAssetError, ?pair, ?bid_order, ?ask_order, ?current_rate);
              case (#NoCredit) #Err(#NoCreditError, ?pair, ?bid_order, ?ask_order, ?current_rate);
              case (#TooLowOrder) #Err(#TooLowOrderError, ?pair, ?bid_order, ?ask_order, ?current_rate);
              case (#VolumeStepViolated x) #Err(#VolumeStepViolated(x), ?pair, ?bid_order, ?ask_order, ?current_rate);
              case (#PriceDigitsOverflow x) #Err(#PriceDigitsOverflow(x), ?pair, ?bid_order, ?ask_order, ?current_rate);
            };
          };
          case (#cancellation(err)) {
            #Err(#CancellationError, null, null, null, null);
          };
          case (#SessionNumberMismatch x) #Err(#SessionNumberMismatch(x), null, null, null, null);
          case (#UnknownPrincipal) #Err(#UnknownPrincipal, null, null, null, null);
          case (#UnknownError x) #Err(#UnknownError(x), null, null, null, null);
        };
      };
    };
  };
};
