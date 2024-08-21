/// A module which contain moc implementation of exchange rate canister for test purposes
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Option "mo:base/Option";
actor CustomXRC {
  public type Asset = { class_ : AssetClass; symbol : Text };
  public type AssetClass = { #Cryptocurrency; #FiatCurrency };
  public type ExchangeRate = {
    metadata : ExchangeRateMetadata;
    rate : Nat64;
    timestamp : Nat64;
    quote_asset : Asset;
    base_asset : Asset;
  };
  public type ExchangeRateError = {
    #AnonymousPrincipalNotAllowed;
    #CryptoQuoteAssetNotFound;
    #FailedToAcceptCycles;
    #ForexBaseAssetNotFound;
    #CryptoBaseAssetNotFound;
    #StablecoinRateTooFewRates;
    #ForexAssetsNotFound;
    #InconsistentRatesReceived;
    #RateLimited;
    #StablecoinRateZeroRate;
    #Other : { code : Nat32; description : Text };
    #ForexInvalidTimestamp;
    #NotEnoughCycles;
    #ForexQuoteAssetNotFound;
    #StablecoinRateNotFound;
    #Pending;
  };
  public type ExchangeRateMetadata = {
    decimals : Nat32;
    forex_timestamp : ?Nat64;
    quote_asset_num_received_rates : Nat64;
    base_asset_num_received_rates : Nat64;
    base_asset_num_queried_sources : Nat64;
    standard_deviation : Nat64;
    quote_asset_num_queried_sources : Nat64;
  };
  public type GetExchangeRateRequest = {
    timestamp : ?Nat64;
    quote_asset : Asset;
    base_asset : Asset;
  };
  public type GetExchangeRateResult = {
    #Ok : ExchangeRate;
    #Err : ExchangeRateError;
  };

  var rate_ : Nat64 = 9_856_521_536;
  var decimals_ : Nat32 = 9;

  public func setRate(rate : Nat64, decimals : Nat32) : async () {
    rate_ := rate;
    decimals_ := decimals;
  };

  public func get_exchange_rate(req : GetExchangeRateRequest) : async GetExchangeRateResult {
    #Ok({
      metadata = {
        decimals = decimals_;
        forex_timestamp = null;
        quote_asset_num_received_rates = 4;
        base_asset_num_received_rates = 7;
        base_asset_num_queried_sources = 9;
        standard_deviation = 5_418_422;
        quote_asset_num_queried_sources = 7;
      };
      rate = rate_;
      timestamp = Option.get<Nat64>(req.timestamp, 0);
      quote_asset = req.quote_asset;
      base_asset = req.base_asset;
    });
  }
}