/// A module which contain implementation of price making for market maker bot
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Float "mo:base/Float";

module PriceMakerModule {
  let market_volatility : Nat = 0; // Temporary set ot 0 to avoid influence at price, will calulate in next version
  let demand_factor : Nat = 1; // Temporary set ot 1 to avoid influence at price, will calulate in next version
  let supply_factor : Nat = 1; // Temporary set ot 1 to avoid influence at price, will calulate in next version

  public func calculatePrices(last_trade_price : Float, total_bid_volume : Nat, total_ask_volume : Nat, base_spread : Float) : (Float, Float) {
    let total_volume = total_bid_volume + total_ask_volume;
    let demand_ratio = Float.fromInt(total_bid_volume) / Float.fromInt(total_volume);
    let supply_ratio = Float.fromInt(total_ask_volume) / Float.fromInt(total_volume);

    let adjusted_spread = base_spread * (1 + Float.fromInt(market_volatility));

    let adjusted_bid_price : Float = last_trade_price * (1 - adjusted_spread * supply_ratio * Float.fromInt(supply_factor));
    let adjusted_ask_price : Float = last_trade_price * (1 + adjusted_spread * demand_ratio * Float.fromInt(demand_factor));

    (adjusted_bid_price, adjusted_ask_price);
  };
};
