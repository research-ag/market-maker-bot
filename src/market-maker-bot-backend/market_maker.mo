/// A module which contain implementation of market maker execution
/// Contain public execute function which is require pair information, oracle and auction wrapper instances
/// also contain all necessary types and functions to calculate prices and volumes
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Int32 "mo:base/Int32";
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

  type DecimalsInfo = {
    base_decimals : Nat32;
    quote_decimals : Nat32;
  };

  public type CreditsInfo = {
    base_credit : Nat;
    quote_credit : Nat;
  };

  public type OrderInfo = {
    amount : Nat;
    price : Float;
  };

  public type MarketPair = {
    base_principal : Principal;
    base_symbol : Text;
    base_decimals : Nat32;
    base_credits : Nat;
    quote_principal : Principal;
    quote_symbol : Text;
    quote_decimals : Nat32;
    quote_credits : Nat;
    spread_value : Float;
  };


  let digits : Float = 5;

  func limitPrecision(x : Float) : Float {
    let e = - Float.log(x) / 2.302_585_092_994_045;
    let e1 = Float.floor(e) + digits;
    Float.floor(x * 10 ** e1) * 10 ** -e1;
  };

  func getPrices(spread : Float, currency_rate : Float) : PricesInfo {
    {
      bid_price = limitPrecision(currency_rate * (1.0 - spread));
      ask_price = limitPrecision(currency_rate * (1.0 + spread));
    };
  };

  func calculateVolumeStep(price : Float) : Int {
    let p = price / Float.fromInt(10 ** 3);
    if (p >= 1) return 1;
    let zf = - Float.log(p) / 2.302_585_092_994_045;
    Int.abs(10 ** Float.toInt(zf));
  };

  func getVolumes(credits : CreditsInfo, prices : PricesInfo, decimals : DecimalsInfo) : ValumesInfo {
    let volume_step = calculateVolumeStep(prices.bid_price);

    let quote_credit : Float = Float.fromInt(credits.quote_credit);
    // calculate multiplicator which help to normalize the price before create
    // the order to the smallest units of the tokens
    let decimals_multiplicator : Float = Float.pow(10, Float.fromInt64(Int32.toInt64((Int32.fromNat32(decimals.quote_decimals) - Int32.fromNat32(decimals.base_decimals)))));

    {
      bid_volume = Int.abs((Float.toInt(quote_credit / prices.bid_price * decimals_multiplicator) / volume_step) * volume_step);
      ask_volume = Int.abs((credits.base_credit / volume_step) * volume_step);
    }
  };

  public func execute(pair : MarketPair, xrc : OracleWrapper.Self, ac : AuctionWrapper.Self) : async* {
    #Ok : (OrderInfo, OrderInfo, Float);
    #Err : U.ExecutionError;
  } {
    let current_rate_result = await* xrc.getExchangeRate(pair.base_symbol, pair.quote_symbol);

    switch (current_rate_result) {
      case (#Ok(current_rate)) {
        let { bid_price; ask_price } = getPrices(pair.spread_value, current_rate);
        let { bid_volume; ask_volume } = getVolumes(
          { base_credit = pair.base_credits; quote_credit = pair.quote_credits },
          { bid_price; ask_price },
          { base_decimals = pair.base_decimals; quote_decimals = pair.quote_decimals },
        );

        let bid_order : OrderInfo = {
          amount = bid_volume;
          price = bid_price;
        };
        let ask_order : OrderInfo = {
          amount = ask_volume;
          price = ask_price;
        };

        let replace_orders_result = await* ac.replaceOrders(pair.base_principal, bid_order, ask_order);

        switch (replace_orders_result) {
          case (#Ok(_)) #Ok(bid_order, ask_order, current_rate);
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
              case (#UnknownError) #Err(#UnknownError);
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
};
