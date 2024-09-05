/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Float "mo:base/Float";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import OracleDefinitions "./oracle_definitions";

module {
  public class Self(oracle_principal : Principal) {
    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    func calculateRate(rate : Nat64, decimals : Nat32) : Float {
      let exponent : Float = Float.fromInt(Nat32.toNat(decimals));
      Float.fromInt(Nat64.toNat(rate)) / Float.pow(10, exponent);
    };

    public func getExchangeRate(base : Text, quote : Text) : async* {
      #Ok : Float;
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
          #Ok(calculateRate(success.rate, success.metadata.decimals));
        };
        case (#Err(_)) {
          #Err(#ErrorGetRates);
        };
      };
    };
  };
};
