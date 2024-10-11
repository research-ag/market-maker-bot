import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Error "mo:base/Error";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import AuctionWrapper "./auction_wrapper";
import MarketMaker "./market_maker";
import Tokens "./tokens";
import U "./utils";

module TradingPairsRegistry {

  public type SharedDataV1 = AssocList.AssocList<Text, MarketMaker.MarketPair>;

  public func defaultSharedDataV1() : SharedDataV1 = null;

  public class TradingPairsRegistry() {

    var quote : ?MarketMaker.TokenDescription = null;

    var registry : AssocList.AssocList<Text, MarketMaker.MarketPair> = null;

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

    func reserveQuoteCredits(c : AssocList.AssocList<Principal, Nat>) : AssocList.AssocList<Principal, Nat> {
      var credits = c;
      for ((_, pair) in List.toIter(registry)) {
        if (pair.quote_credits > 0) {
          var quoteFreeCredits = U.getByKeyOrDefault<Principal, Nat>(credits, quoteInfo().principal, Principal.equal, 0);
          if (quoteFreeCredits <= pair.quote_credits) {
            pair.quote_credits := quoteFreeCredits;
            quoteFreeCredits := 0;
          } else {
            quoteFreeCredits -= pair.quote_credits;
          };
          let (upd, _) = AssocList.replace<Principal, Nat>(credits, quoteInfo().principal, Principal.equal, ?quoteFreeCredits);
          credits := upd;
        };
      };
      credits;
    };

    public func setQuoteBalance(auction : AuctionWrapper.Self, baseSymbol : Text, balance : Nat) : async* () {
      let ?pair = getPair(baseSymbol) else throw Error.reject("Trading pair not found");
      if (pair.quote_credits < balance) {
        var credits = await* pullCredits(auction);
        credits := reserveQuoteCredits(credits);
        let quoteCredits = U.getByKeyOrDefault<Principal, Nat>(credits, quoteInfo().principal, Principal.equal, 0);
        if (quoteCredits + pair.quote_credits < balance) {
          throw Error.reject("Insufficient quote token balance");
        };
      };
      pair.quote_credits := balance;
    };

    public func refreshCredits(auction : AuctionWrapper.Self) : async* () {
      // pull pure credits from the auction
      var credits = await* pullCredits(auction);
      // decrement already reserved funds from quote token(s) credits
      credits := reserveQuoteCredits(credits);
      // update values in the registry
      for ((_, pair) in List.toIter(registry)) {
        pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(credits, pair.base.principal, Principal.equal, 0);
      };
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

    func pullCredits(auction : AuctionWrapper.Self) : async* AssocList.AssocList<Principal, Nat> {
      let supported_tokens = await* auction.getSupportedTokens();
      for (token in supported_tokens.vals()) {
        ignore await* auction.notify(token);
      };
      await* auction.getCredits();
    };

    public func share() : SharedDataV1 {
      registry;
    };

    public func unshare(data : SharedDataV1) {
      registry := data;
    };

  };

};
