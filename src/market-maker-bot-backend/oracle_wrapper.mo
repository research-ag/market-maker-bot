/// A module which contain oracle wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Array "mo:base/Array";
import Blob "mo:base/Blob";
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

import OracleDefinitions "./oracle_definitions";
import HttpAgent "./http_agent";

module {

  public func transform_metal_price_api_response(raw : HttpAgent.HttpResponsePayload) : HttpAgent.HttpResponsePayload {
    // example response:
    // "{"success":true,"base":"USD","timestamp":1731494166,"rates":{"USDXAU":2609.5577138917,"XAU":0.0003832067}}""
    // transformer returns:
    // "2609.5577138917"
    let fallbackResponse = {
      status = raw.status;
      body = raw.body;
      headers = [];
    };
    switch (raw.status) {
      case (200) {
        let ?json = Text.decodeUtf8(Blob.fromArray(raw.body)) else return fallbackResponse;
        if (not Text.startsWith(json, #text("{\"success\":true"))) {
          return fallbackResponse;
        };
        // skip 5 first json values (success, base, timestamp, rates, USDXAU)
        var skipColons = 5;
        let chars = json.chars();
        while (skipColons > 0) {
          switch (chars.next()) {
            case (null) return fallbackResponse;
            case (?':') skipColons -= 1;
            case (_) {};
          };
        };
        // read value
        var valueStr = "";
        label L while (true) {
          switch (chars.next()) {
            case (null) return fallbackResponse;
            case (?',') break L;
            case (?x) valueStr := valueStr # Text.fromChar(x);
          };
        };
        {
          status = raw.status;
          body = valueStr |> Text.encodeUtf8(_) |> Blob.toArray(_);
          headers = [];
        };
      };
      case (_) fallbackResponse;
    };
  };

  public class Self(oracle_principal : Principal, httpAgent : HttpAgent.HttpAgent) {
    let xrc : OracleDefinitions.Self = actor (Principal.toText(oracle_principal));

    let neutriniteOracle : (
      actor {
        get_latest : () -> async [((Nat, Nat), Text, Float)];
      }
    ) = actor ("u45jl-liaaa-aaaam-abppa-cai");

    func calculateRate(rate : Nat64, decimals : Nat32) : Float {
      let exponent : Float = Float.fromInt(Nat32.toNat(decimals));
      Float.fromInt(Nat64.toNat(rate)) / Float.pow(10, exponent);
    };

    public func fetchRates(quoteSymbol : Text, baseSymbols : [Text]) : async* [{
      #Ok : Float;
      #Err : { #ErrorGetRates : Text };
    }] {
      Debug.print("Fetching rates..");
      let calls : [var { #Ok : async { #Ok : Float; #Err : { #ErrorGetRates : Text } }; #Err : Text }] = Array.init(baseSymbols.size(), #Err("N/A"));
      for (i in baseSymbols.keys()) {
        try {
          calls[i] := #Ok(getExchangeRate(baseSymbols[i], quoteSymbol));
        } catch (err) {
          calls[i] := #Err("Schedule call error: " # Error.message(err));
        };
      };
      var res = Array.init<{ #Ok : Float; #Err : { #ErrorGetRates : Text } }>(baseSymbols.size(), #Err(#ErrorGetRates("N/A")));
      label L for (i in calls.keys()) {
        res[i] := switch (calls[i]) {
          case (#Ok call) {
            try {
              await call;
            } catch (err) {
              #Err(#ErrorGetRates("Call error: " # Error.message(err)));
            };
          };
          case (#Err msg) #Err(#ErrorGetRates(msg));
        };
      };
      Debug.print("Rates fetched: " # debug_show res);
      Array.freeze(res);
    };

    public func getExchangeRate(base : Text, quote : Text) : async {
      #Ok : Float;
      #Err : {
        #ErrorGetRates : Text;
      };
    } {
      if (base == "TCYCLES") {
        let key = switch (base) {
          case ("TCYCLES") "XTC/USD";
          case (_) Prim.trap("Can never happen: unknown token for neutrinite");
        };
        let results = await neutriniteOracle.get_latest();
        var rate : Float = 0;
        label l for (x in results.vals()) {
          if (x.1 == key) {
            rate := x.2;
            break l;
          };
        };
        if (rate == 0) {
          #Err(#ErrorGetRates("Neutrinite oracle did not provide key " # key));
        } else {
          #Ok(rate);
        };
      } else if (base == "GLDT") {
        try {
          let raw = await* httpAgent.simpleGet(
            "api.metalpriceapi.com",
            "v1/latest?api_key=739362f0a189bfb85a09c88715ee9d5e&currencies=XAU",
            [
              { name = "accept"; value = "application/json" },
            ],
            ?"USDXAU_rate",
          );
          let chars = raw.body.chars();
          var valueStr = "";
          var decimals : Int = 0;
          var decimalFlag = false;
          label L while (true) {
            switch (chars.next()) {
              case (null) break L;
              case (?'.') decimalFlag := true;
              case (?x) {
                valueStr := valueStr # Text.fromChar(x);
                if (decimalFlag) {
                  decimals += 1;
                };
              };
            };
          };
          let ?v = Nat.fromText(valueStr) else return #Err(#ErrorGetRates("Cannot parse Metal Price API response: " # raw.body));
          #Ok(Float.fromInt(v) / 10 ** Float.fromInt(decimals));
        } catch (err) {
          #Err(#ErrorGetRates("Metal Price API error: " # Error.message(err)));
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
      };
    };
  };
};
