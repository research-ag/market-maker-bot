/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import OracleDefinitions "./oracle_definitions";

module {
  public type CurrencyRate = {
    rate : Nat64;
    decimals : Nat32;
  };

  public class Self(oracle_principal : Principal) {
    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    public func getExchangeRate(base : Text, quote : Text) : async* {
      #Ok : CurrencyRate;
      #Err : {
        #ErrorGetRates;
      };
    } {
      let request : OracleDefinitions.GetExchangeRateRequest = {
        timestamp = null;
        quote_asset = {
          class_ = #Cryptocurrency;
          symbol = quote;
        };
        base_asset = {
          class_ = #Cryptocurrency;
          symbol = base;
        };
      };

      ////////////////////////////////////
      Cycles.add<system>(10_000_000_000);
      ////////////////////////////////////

      let response = await xrc.get_exchange_rate(request);

      switch (response) {
        case (#Ok(success)) {
          let currency_rate : CurrencyRate = {
            rate = success.rate;
            decimals = success.metadata.decimals;
          };

          return #Ok(currency_rate);
        };
        case (#Err(_)) {
          return #Err(#ErrorGetRates);
        };
      };
    };
  }
}