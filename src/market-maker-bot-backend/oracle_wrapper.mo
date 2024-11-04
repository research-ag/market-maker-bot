/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";

import OracleDefinitions "./oracle_definitions";
import U "./utils";

module {
  public class Self(oracle_principal : Principal) {
    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    let xrc2 : (
      actor {
        get_latest : () -> async [((Nat, Nat), Text, Float)];
      }
    ) = actor ("u45jl-liaaa-aaaam-abppa-cai");

    func calculateRate(rate : Nat64, decimals : Nat32) : Float {
      let exponent : Float = Float.fromInt(Nat32.toNat(decimals));
      Float.fromInt(Nat64.toNat(rate)) / Float.pow(10, exponent);
    };

    public func fetchRates(quoteSymbol : Text, baseSymbols : [Text]) : async* [?Float] {
      Debug.print("Fetching rates..");
      let calls : [var ?(async { #Ok : Float; #Err : { #ErrorGetRates } })] = Array.init(baseSymbols.size(), null);
      for (i in baseSymbols.keys()) {
        try {
          calls[i] := ?(getExchangeRate(baseSymbols[i], quoteSymbol));
        } catch (_) {};
      };
      var res = Array.init<?Float>(baseSymbols.size(), null);
      label L for (i in calls.keys()) {
        let ?call = calls[i] else continue L;
        try {
          res[i] := U.upperResultToOption(await call);
        } catch (_) {};
      };
      Debug.print("Rates fetched: " # debug_show res);
      Array.freeze(res);
    };

    public func getExchangeRate(base : Text, quote : Text) : async {
      #Ok : Float;
      #Err : {
        #ErrorGetRates;
      };
    } {
      if (base == "TCYCLES") {
        let results = await xrc2.get_latest();
        var rate : Float = 0;
        label l for (x in results.vals()) {
          if (x.1 == "XTC/USD") {
            rate := x.2;
            break l;
          };
        };
        if (rate == 0) {
          #Err(#ErrorGetRates);
        } else {
          #Ok(rate);
        };
      } else {
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
};
