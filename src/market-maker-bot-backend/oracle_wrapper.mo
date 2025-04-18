/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Float "mo:base/Float";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import Vec "mo:vector";

import OracleDefinitions "./oracle_definitions";

module {

  public class Self(oracle_principal : Principal) {

    // how many times rate for single base token considered to be valid.
    // In case of error response we can use previous successful response as soon as
    // error did not already happen CACHE_TTL times in a row
    let CACHE_TTL = 1;

    var ratesCache : AssocList.AssocList<Text, { rate : Float; var ttl : Nat }> = List.nil();
    private func cacheRate(symbol : Text, rate : Float) {
      let (upd, _) = AssocList.replace(ratesCache, symbol, Text.equal, ?{ rate; var ttl = CACHE_TTL });
      ratesCache := upd;
    };
    private func popCachedRate(symbol : Text) : ?Float {
      let ?entry = AssocList.find(ratesCache, symbol, Text.equal) else return null;
      entry.ttl -= 1;
      if (entry.ttl == 0) {
        let (upd, _) = AssocList.replace(ratesCache, symbol, Text.equal, null);
        ratesCache := upd;
      };
      ?entry.rate;
    };

    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    let neutriniteOracle : (
      actor {
        get_latest : () -> async [((Nat, Nat), Text, Float)];
      }
    ) = actor ("u45jl-liaaa-aaaam-abppa-cai");

    let metalPriceApiOracle : (
      actor {
        queryRates : ([Text]) -> async [(Text, ?{ timestamp : Nat; value : Float })];
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
      var metalPriceCall : ?(async [(Text, ?{ timestamp : Nat; value : Float })]) = null;

      // fill call info and schedule all cross-canister calls at once
      for (i in baseSymbols.keys()) {
        switch (baseSymbols[i]) {
          // case "TCYCLES" Vec.add(neutriniteSymbolPairs, (i, "TCYCLES", "XTC/USD"));
          case "GLDT" Vec.add(metalPriceSymbolPairs, (i, "GLDT", "USDXAU"));
          case "BTC" Vec.add(metalPriceSymbolPairs, (i, "BTC", "USDBTC"));
          case "ETH" Vec.add(metalPriceSymbolPairs, (i, "ETH", "USDETH"));
          case "EURC" Vec.add(metalPriceSymbolPairs, (i, "EURC", "USDEUR"));
          case symbol {
            let (baseSymbol, baseClass) = switch (symbol) {
              case "TCYCLES" ("XDR", #FiatCurrency);
              case x(x, #Cryptocurrency);
            };
            let request : OracleDefinitions.GetExchangeRateRequest = {
              timestamp = null;
              quote_asset = {
                class_ = #Cryptocurrency;
                symbol = quoteSymbol;
              };
              base_asset = {
                class_ = baseClass;
                symbol = baseSymbol;
              };
            };
            try {
              Vec.add(xrcCalls, (i, (with cycles = 10_000_000_000) xrc.get_exchange_rate(request)));
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
              let rate = calculateRate(success.rate, success.metadata.decimals);
              cacheRate(baseSymbols[i], rate);
              #Ok(rate);
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
                cacheRate(baseSymbols[i], rate);
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
                case (?{ value; timestamp }) {
                  if (timestamp < minSyncTimestamp) {
                    #Err(#ErrorGetRates("Metal Price API rate is too old: " # Nat.toText(timestamp)));
                  } else {
                    let rate = if (localSymbol == "GLDT") {
                      value / 3110.35;
                    } else {
                      value;
                    };
                    cacheRate(baseSymbols[i], rate);
                    #Ok(rate);
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
      // try to use cache for rates which resulted in error
      for (i in baseSymbols.keys()) {
        switch (res[i]) {
          case (#Ok _) {};
          case (#Err _) {
            switch (popCachedRate(baseSymbols[i])) {
              case (?rate) {
                Debug.print("Use cached rate for " # baseSymbols[i]);
                res[i] := #Ok(rate);
              };
              case (null) {};
            };
          };
        };
      };
      Debug.print("Rates fetched: " # debug_show res);
      Array.freeze(res);
    };
  };
};
