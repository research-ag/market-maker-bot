/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:core/Array";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Float "mo:core/Float";
import List "mo:core/List";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";

import Prim "mo:prim";

import OracleDefinitions "oracle_definitions";

module {

  public class Self(oracle_principal : Principal) {

    // how many times rate for single base token considered to be valid.
    // In case of error response we can use previous successful response as soon as
    // error did not already happen CACHE_TTL times in a row
    let CACHE_TTL = 2;

    let ratesCache : Map.Map<Text, { rate : Float; var ttl : Nat }> = Map.empty();
    private func cacheRate(symbol : Text, rate : Float) {
      Map.add(ratesCache, Text.compare, symbol, { rate; var ttl = CACHE_TTL });
    };
    private func popCachedRate(symbol : Text) : ?Float {
      let ?entry = Map.get(ratesCache, Text.compare, symbol) else return null;
      entry.ttl -= 1;
      if (entry.ttl == 0) {
        Map.remove(ratesCache, Text.compare, symbol);
      };
      ?entry.rate;
    };

    let xrc : OracleDefinitions.Self = actor (oracle_principal.toText());

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
      let exponent : Float = Float.fromInt(decimals.toNat());
      rate.toNat().toFloat() / Float.pow(10, exponent);
    };

    public func fetchRates(quoteSymbol : Text, baseSymbols : [Text]) : async* [{
      #Ok : Float;
      #Err : { #ErrorGetRates : Text };
    }] {
      Debug.print("Fetching rates..");
      let res = VarArray.repeat<{ #Ok : Float; #Err : { #ErrorGetRates : Text } }>(#Err(#ErrorGetRates("N/A")), baseSymbols.size());

      // define call info
      let xrcCalls : List.List<(i : Nat, async OracleDefinitions.GetExchangeRateResult)> = List.empty();

      let neutriniteSymbolPairs : List.List<(i : Nat, localSymbol : Text, remoteSymbol : Text)> = List.empty();
      var neutriniteCall : ?(async [((Nat, Nat), Text, Float)]) = null;

      let metalPriceSymbolPairs : List.List<(i : Nat, localSymbol : Text, remoteSymbol : Text)> = List.empty();
      var metalPriceCall : ?(async [(Text, ?{ timestamp : Nat; value : Float })]) = null;

      // fill call info and schedule all cross-canister calls at once
      for (i in baseSymbols.keys()) {
        switch (baseSymbols[i]) {
          // case "TCYCLES" List.add(neutriniteSymbolPairs, (i, "TCYCLES", "XTC/USD"));
          case "GLDT" List.add(metalPriceSymbolPairs, (i, "GLDT", "USDXAU"));
          case "BTC" List.add(metalPriceSymbolPairs, (i, "BTC", "USDBTC"));
          case "ETH" List.add(metalPriceSymbolPairs, (i, "ETH", "USDETH"));
          case "EURC" List.add(metalPriceSymbolPairs, (i, "EURC", "USDEUR"));
          case symbol {
            let (baseSymbol, baseClass) = switch (symbol) {
              case "TCYCLES" ("XDR", #FiatCurrency);
              case x (x, #Cryptocurrency);
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
              List.add(xrcCalls, (i, (with cycles = 10_000_000_000) xrc.get_exchange_rate(request)));
            } catch (err) {
              res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
            };
          };
        };
      };
      if (neutriniteSymbolPairs.size() > 0) {
        try {
          neutriniteCall := ?(neutriniteOracle.get_latest());
        } catch (err) {
          for ((i, _, _) in neutriniteSymbolPairs.values()) {
            res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
          };
        };
      };
      if (metalPriceSymbolPairs.size() > 0) {
        try {
          metalPriceCall := ?(
            metalPriceApiOracle.queryRates(
              metalPriceSymbolPairs.toArray() |> Array.map<(Nat, Text, remoteSymbol : Text), Text>(_, func((_, _, s)) = s)
            )
          );
        } catch (err) {
          for ((i, _, _) in metalPriceSymbolPairs.values()) {
            res[i] := #Err(#ErrorGetRates("Schedule call error: " # Error.message(err)));
          };
        };
      };

      // actually await cross-canister calls
      for ((i, call) in xrcCalls.values()) {
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
            for ((i, _, remoteSymbol) in neutriniteSymbolPairs.values()) {
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
            for ((i, _, _) in List.values(neutriniteSymbolPairs)) {
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
            let minSyncTimestamp = (Prim.time() / 1_000_000_000 - 6 * 60 * 60).toNat();
            for ((idx, (i, localSymbol, remoteSymbol)) in metalPriceSymbolPairs.enumerate()) {
              res[i] := switch (results[idx].1) {
                case (null) #Err(#ErrorGetRates("Metal Price API did not provide key " # remoteSymbol));
                case (?{ value; timestamp }) {
                  if (timestamp < minSyncTimestamp) {
                    #Err(#ErrorGetRates("Metal Price API rate is too old: " # timestamp.toText()));
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
            for ((i, _, _) in metalPriceSymbolPairs.values()) {
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
      res.toArray();
    };
  };
};
