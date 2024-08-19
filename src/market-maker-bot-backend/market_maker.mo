/// A module which contain implementation of market maker class for one pair
/// Contain implelemtation of manage orders for one iteration, should be called by
/// "orchestrator" each time when we wanna put BID and ASK orders
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Float "mo:base/Float";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Nat32 "mo:base/Nat32";
import Cycles "mo:base/ExperimentalCycles";
import Oracle "./oracle";
import Auction "./auction";

module MarketMakerModule {
  type CurrencyRate = {
    rate : Nat64;
    decimals : Nat32;
  };

  type PricesInfo = {
    bid_price : Float;
    ask_price : Float;
  };

  type ValumesInfo = {
    bid_volume : Nat;
    ask_volume : Nat;
  };

  public type CreditsInfo = {
    base_credit : Nat;
    quote_credit : Nat;
  };

  public type OrderInfo = {
    amount : Nat;
    price : Float;
  };

  public type Asset = {
    principal : Principal;
    symbol : Text;
    decimals : Nat32;
  };

  public type Pair = {
    base : Asset;
    quote : Asset;
    spread_value: Float;
  };

  public type ExecutionError = {
    #PlacementError;
    #CancellationError;
    #UnknownPrincipal;
    #RatesError;
    #ConflictOrderError;
    #UnknownAssetError;
    #NoCreditError;
    #TooLowOrderError;
  };

  public class MarketMaker(pair : Pair, xrc : Oracle.Self, ac : Auction.Self) {
    func getCurrentRate(baseSymbol: Text, quoteSymbol: Text) : async* {
      #Ok : CurrencyRate;
      #Err : {
        #ErrorGetRates;
      }
    } {
      let request: Oracle.GetExchangeRateRequest = {
        timestamp = null;
        quote_asset = { class_ = #Cryptocurrency; symbol = quoteSymbol };
        base_asset = { class_ = #Cryptocurrency; symbol = baseSymbol };
      };
      Cycles.add<system>(10_000_000_000);
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
      }
    };

    func getPrices(spread : Float, currency_rate : CurrencyRate) : PricesInfo {
      let exponent : Float = Float.fromInt64(Int64.fromNat64(Nat32.toNat64(currency_rate.decimals)));
      let float_price : Float = Float.fromInt64(Int64.fromNat64(currency_rate.rate)) / Float.pow(10, exponent);

      {
        bid_price = float_price * (1.0 - spread);
        ask_price = float_price * (1.0 + spread);
      }
    };

    func getVolumes(credits : CreditsInfo, prices : PricesInfo) : ValumesInfo {
      {
        bid_volume = Int.abs(Float.toInt(Float.fromInt(credits.quote_credit) / prices.bid_price)) / 100 * 100;
        ask_volume = (credits.base_credit / 100) * 100;
      }
    };

    func replaceOrders(token: Principal, bid : OrderInfo, ask : OrderInfo) : async* {
      #Ok : [Nat];
      #Err : Auction.ManageOrdersError;
    } {
      let response = await ac.manageOrders(
        ?(#all (?[token])), // cancell all orders for tokens
        [#bid (token, bid.amount, bid.price), #ask (token, ask.amount, ask.price)],
      );


      switch (response) {
        case (#Ok(success)) #Ok(success);
        case (#Err(error)) {
          switch (error) {
            case (#cancellation(_)) {
              let response = await ac.manageOrders(
                ?(#orders ([])),
                [#bid (token, bid.amount, bid.price), #ask (token, ask.amount, ask.price)],
              );

              switch (response) {
                case (#Ok(success)) #Ok(success);
                case (#Err(error)) #Err(error);
              }
            };
            case (_) #Err(error);
          }
        };
      }
    };

    public func execute(credits: CreditsInfo) : async* {
      #Ok: (OrderInfo, OrderInfo);
      #Err : ExecutionError;
    } {
      // let { base_credit; quote_credit } = await* queryCredits(pair.base.principal, pair.quote.principal);
      var current_rate_result : {
        #Ok : CurrencyRate;
        #Err : {
          #ErrorGetRates;
        }
      } = #Err(#ErrorGetRates);
      let { base_credit; quote_credit } = credits;
      try {
        current_rate_result := await* getCurrentRate(pair.base.symbol, pair.quote.symbol);
      } catch (_) {
        ignore await* removeOrders();
        return #Err(#RatesError);
      };

      switch (current_rate_result) {
        case (#Ok(current_rate)) {
          let { bid_price; ask_price } = getPrices(pair.spread_value, current_rate);
          let { bid_volume; ask_volume } = getVolumes({ base_credit; quote_credit }, { bid_price; ask_price });

          let bid_order : OrderInfo = {
            amount = bid_volume;
            price = bid_price;
          };
          let ask_order : OrderInfo = {
            amount = ask_volume;
            price = ask_price;
          };

          let replace_orders_result = await* replaceOrders(pair.base.principal, bid_order, ask_order);

          switch (replace_orders_result) {
            case (#Ok(_)) #Ok(bid_order, ask_order);
            case (#Err(err)) {
              ignore await* removeOrders();
              switch (err) {
                case (#placement(err)) {
                  switch (err.error) {
                    case (#ConflictingOrder(_)) #Err(#ConflictOrderError);
                    case (#UnknownAsset) #Err(#UnknownAssetError);
                    case (#NoCredit) #Err(#NoCreditError);
                    case (#TooLowOrder) #Err(#TooLowOrderError);
                  }
                };
                case (#cancellation(err)) #Err(#CancellationError);
                case (#UnknownPrincipal) #Err(#UnknownPrincipal);
              }
            };
          }
        };
        case (#Err(err)) {
          ignore await* removeOrders();
          switch (err) {
            case (#ErrorGetRates) #Err(#RatesError);
          }
        };
      }
    };

    public func removeOrders() : async* {
      #Ok;
      #Err : {
        #CancellationError;
      };
    } {
      try {
        let response = await ac.manageOrders(
          ?(#all (?[pair.base.principal])), // cancell all orders for tokens
          [],
        );

        switch (response) {
          case (#Ok(_)) #Ok;
          case (#Err(_)) #Err(#CancellationError);
        }
      } catch (_) {
        return #Err(#CancellationError);
      }
    };

    public func getPair() : (Pair) {
      pair;
    }
  }
}
