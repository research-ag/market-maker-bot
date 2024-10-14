import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Error "mo:base/Error";
import Int "mo:base/Int";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import AuctionWrapper "./auction_wrapper";
import MarketMaker "./market_maker";
import Tokens "./tokens";
import U "./utils";

module TradingPairsRegistry {

  public type SharedDataV1 = {
    registry : AssocList.AssocList<Text, MarketMaker.MarketPair>;
    quoteReserve : Nat;
  };

  public func defaultSharedDataV1() : SharedDataV1 = {
    registry = null;
    quoteReserve = 0;
  };

  public class TradingPairsRegistry() {

    var quote : ?MarketMaker.TokenDescription = null;

    var registry : AssocList.AssocList<Text, MarketMaker.MarketPair> = null;
    var quoteReserve : Nat = 0;

    public func quoteInfo() : MarketMaker.TokenDescription = U.requireMsg(quote, "Not initialized");

    public func nPairs() : Nat = List.size(registry);

    public func getPairs() : [MarketMaker.MarketPair] {
      let items = List.toArray(registry);
      Array.tabulate<MarketMaker.MarketPair>(
        items.size(),
        func(i : Nat) : MarketMaker.MarketPair = items[i].1,
      );
    };

    public func getPair(baseSymbol : Text) : ?MarketMaker.MarketPair {
      AssocList.find<Text, MarketMaker.MarketPair>(registry, baseSymbol, Text.equal);
    };

    public func setQuoteBalance(baseSymbol : Text, balance : { #set : Nat; #inc : Nat; #dec : Nat }) : async* Nat {
      let ?pair = getPair(baseSymbol) else throw Error.reject("Trading pair not found");
      var balanceInc : Int = switch (balance) {
        case (#set x) x - pair.quote_credits;
        case (#inc x) x;
        case (#dec x) Int.max(-pair.quote_credits, -x);
      };
      if (balanceInc > 0 and quoteReserve < balanceInc) {
        throw Error.reject("Insufficient quote token balance");
      };
      pair.quote_credits := Int.abs(pair.quote_credits + balanceInc);
      quoteReserve := Int.abs(quoteReserve - balanceInc);
      pair.quote_credits;
    };

    public func refreshCredits(auction : AuctionWrapper.Self) : async* () {
      // pull pure credits from the auction
      let supported_tokens = await* auction.getSupportedTokens();
      for (token in supported_tokens.vals()) {
        ignore await* auction.notify(token);
      };
      let credits = await* auction.getCredits();
      // calculate quote credits reserve, update values in the registry
      var quoteFreeCredits = U.getByKeyOrDefault<Principal, Nat>(credits, quoteInfo().principal, Principal.equal, 0);
      for ((_, pair) in List.toIter(registry)) {
        pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(credits, pair.base.principal, Principal.equal, 0);
        if (pair.quote_credits > 0) {
          if (quoteFreeCredits <= pair.quote_credits) {
            pair.quote_credits := quoteFreeCredits;
            quoteFreeCredits := 0;
          } else {
            quoteFreeCredits -= pair.quote_credits;
          };
        };
      };
      quoteReserve := quoteFreeCredits;
    };

    public func refreshTokens(auction : AuctionWrapper.Self, default_spread_value : Float) : async* (Principal, [Principal]) {
      let quote_token = await* auction.getQuoteToken();
      let supported_tokens = await* auction.getSupportedTokens();
      let tokens_info = Tokens.getTokensInfo();
      let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, quote_token, Principal.equal, "Error get quote token info");
      quote := ?{
        principal = quote_token;
        symbol = quote_token_info.symbol;
        decimals = quote_token_info.decimals;
      };

      for (token in supported_tokens.vals()) {
        if (not Principal.equal(token, quote_token)) {
          switch (AssocList.find(tokens_info, token, Principal.equal)) {
            case (?_) {
              let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, token, Principal.equal, "Error get base token info");
              let pair = {
                base = {
                  principal = token;
                  symbol = base_token_info.symbol;
                  decimals = base_token_info.decimals;
                };
                var base_credits = 0;
                var quote_credits = 0;
                var spread_value = default_spread_value;
              };

              let (upd, oldValue) = AssocList.replace<Text, MarketMaker.MarketPair>(
                registry,
                pair.base.symbol,
                Text.equal,
                ?pair,
              );
              switch (oldValue) {
                case (?_) {};
                case (null) registry := upd;
              };
            };
            case (_) {};
          };
        };
      };
      (quote_token, supported_tokens);
    };

    public func share() : SharedDataV1 {
      { registry; quoteReserve };
    };

    public func unshare(data : SharedDataV1) {
      registry := data.registry;
      quoteReserve := data.quoteReserve;
    };

  };

};
