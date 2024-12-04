/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Cycles "mo:base/ExperimentalCycles";

import Vec "mo:vector";

import OracleDefinitions "./oracle_definitions";

module {

  public class Self(oracle_principal : Principal) {
    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    let neutriniteOracle : (
      actor {
        get_latest : () -> async [((Nat, Nat), Text, Float)];
      }
    ) = actor ("u45jl-liaaa-aaaam-abppa-cai");

    let metalPriceApiOracle : (
      actor {
        queryRates : ([Text]) -> async [(Text, ?{ apiTimestamp : Nat; value : Float })];
      }
    ) = actor ("k2ic6-3yaaa-aaaao-a3u6a-cai");

    func calculateRate(rate : Nat64, decimals : Nat32) : Float {
      let exponent : Float = Float.fromInt(Nat32.toNat(decimals));
      Float.fromInt(Nat64.toNat(rate)) / Float.pow(10, exponent);
    };

    public func fetchRates(quoteSymbol : Text, baseSymbols : [Text]) : async* [{
      #Ok : Float;
      #Err : { #ErrorGetRates : Text };
    }] {
      Debug.print("Fetching rates..");
      var res = Array.init<{ #Ok : Float; #Err : { #ErrorGetRates : Text } }>(baseSymbols.size(), #Err(#ErrorGetRates("N/A")));

      // define call info
      let xrcCalls : Vec.Vector<(i : Nat, async OracleDefinitions.GetExchangeRateResult)> = Vec.new();

      let neutriniteSymbolPairs : Vec.Vector<(i : Nat, localSymbol : Text, remoteSymbol : Text)> = Vec.new();
      var neutriniteCall : ?(async [((Nat, Nat), Text, Float)]) = null;

      let metalPriceSymbolPairs : Vec.Vector<(i : Nat, localSymbol : Text, remoteSymbol : Text)> = Vec.new();
      var metalPriceCall : ?(async [(Text, ?{ apiTimestamp : Nat; value : Float })]) = null;

      // fill call info and schedule all cross-canister calls at once
      for (i in baseSymbols.keys()) {
        switch (baseSymbols[i]) {
          case "TCYCLES" Vec.add(neutriniteSymbolPairs, (i, "TCYCLES", "XTC/USD"));
          case "GLDT" Vec.add(metalPriceSymbolPairs, (i, "GLDT", "USDXAU"));
          case "BTC" Vec.add(metalPriceSymbolPairs, (i, "BTC", "USDBTC"));
          case "ETH" Vec.add(metalPriceSymbolPairs, (i, "ETH", "USDETH"));
          case _ {
            let request : OracleDefinitions.GetExchangeRateRequest = {
              timestamp = null;
              quote_asset = {
                class_ = #Cryptocurrency;
                symbol = quoteSymbol;
              };
              base_asset = {
                class_ = #Cryptocurrency;
                symbol = baseSymbols[i];
              };
            };
            Cycles.add<system>(10_000_000_000);
            try {
              Vec.add(xrcCalls, (i, xrc.get_exchange_rate(request)));
            } catch (err) {
              res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
            };
          };
        };
      };
      if (Vec.size(neutriniteSymbolPairs) > 0) {
        try {
          neutriniteCall := ?(neutriniteOracle.get_latest());
        } catch (err) {
          for ((i, _, _) in Vec.vals(neutriniteSymbolPairs)) {
            res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
          };
        };
      };
      if (Vec.size(metalPriceSymbolPairs) > 0) {
        try {
          metalPriceCall := ?(
            metalPriceApiOracle.queryRates(
              Vec.toArray(metalPriceSymbolPairs) |> Array.map<(Nat, Text, remoteSymbol : Text), Text>(_, func((_, _, s)) = s)
            )
          );
        } catch (err) {
          for ((i, _, _) in Vec.vals(metalPriceSymbolPairs)) {
            res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
          };
        };
      };

      // actually await cross-canister calls
      for ((i, call) in Vec.vals(xrcCalls)) {
        try {
          let response = await call;
          res[i] := switch (response) {
            case (#Ok(success)) {
              #Ok(calculateRate(success.rate, success.metadata.decimals));
            };
            case (#Err(err)) #Err(
              #ErrorGetRates(
                switch (err) {
                  case (#AnonymousPrincipalNotAllowed) "#AnonymousPrincipalNotAllowed";
                  case (#CryptoQuoteAssetNotFound) "#CryptoQuoteAssetNotFound";
                  case (#FailedToAcceptCycles) "#FailedToAcceptCycles";
                  case (#ForexBaseAssetNotFound) "#ForexBaseAssetNotFound";
                  case (#CryptoBaseAssetNotFound) "#CryptoBaseAssetNotFound";
                  case (#StablecoinRateTooFewRates) "#StablecoinRateTooFewRates";
                  case (#ForexAssetsNotFound) "#ForexAssetsNotFound";
                  case (#InconsistentRatesReceived) "#InconsistentRatesReceived";
                  case (#RateLimited) "#RateLimited";
                  case (#StablecoinRateZeroRate) "#StablecoinRateZeroRate";
                  case (#Other { code; description }) "#Other: " # description # " (code " #debug_show code # ")";
                  case (#ForexInvalidTimestamp) "#ForexInvalidTimestamp";
                  case (#NotEnoughCycles) "#NotEnoughCycles";
                  case (#ForexQuoteAssetNotFound) "#ForexQuoteAssetNotFound";
                  case (#StablecoinRateNotFound) "#StablecoinRateNotFound";
                  case (#Pending) "#Pending";
                }
              )
            );
          };
        } catch (err) {
          res[i] := #Err(#ErrorGetRates("Call error: " # Error.message(err)));
        };
      };
      switch (neutriniteCall) {
        case (?call) {
          try {
            let results = await call;
            for ((i, _, remoteSymbol) in Vec.vals(neutriniteSymbolPairs)) {
              var rate : Float = 0;
              label l for (x in results.vals()) {
                if (x.1 == remoteSymbol) {
                  rate := x.2;
                  break l;
                };
              };
              res[i] := if (rate == 0) {
                #Err(#ErrorGetRates("Neutrinite oracle did not provide key " # remoteSymbol));
              } else {
                #Ok(rate);
              };
            };
          } catch (err) {
            for ((i, _, _) in Vec.vals(neutriniteSymbolPairs)) {
              res[i] := #Err(#ErrorGetRates("Call error: " # Error.message(err)));
            };
          };
        };
        case (null) {};
      };
      switch (metalPriceCall) {
        case (?call) {
          try {
            let results = await call;
            // ignore rates, synchronised more than 6 hours ago
            let minSyncTimestamp = Nat64.toNat(Prim.time() / 1_000_000_000 - 6 * 60 * 60);
            for (((i, localSymbol, remoteSymbol), idx) in Vec.items(metalPriceSymbolPairs)) {
              res[i] := switch (results[idx].1) {
                case (null) #Err(#ErrorGetRates("Metal Price API did not provide key " # remoteSymbol));
                case (?{ value; apiTimestamp }) {
                  if (apiTimestamp < minSyncTimestamp) {
                    #Err(#ErrorGetRates("Metal Price API rate is too old: " # Nat.toText(apiTimestamp)));
                  } else {
                    if (localSymbol == "GLDT") {
                      #Ok(value / 3110.35);
                    } else {
                      #Ok(value);
                    };
                  };
                };
              };
            };
          } catch (err) {
            for ((i, _, _) in Vec.vals(metalPriceSymbolPairs)) {
              res[i] := #Err(#ErrorGetRates("Call error: " # Error.message(err)));
            };
          };
        };
        case (null) {};
      };
      Debug.print("Rates fetched: " # debug_show res);
      Array.freeze(res);
    };
  };
};
