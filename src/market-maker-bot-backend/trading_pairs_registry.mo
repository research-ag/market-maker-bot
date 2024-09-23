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

  public type SharedDataV1 = AssocList.AssocList<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair>;

  public func defaultSharedDataV1() : SharedDataV1 = null;

  public class TradingPairsRegistry() {

    var registry : AssocList.AssocList<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair> = null;

    public func nPairs() : Nat = List.size(registry);

    public func getPairs() : [MarketMaker.MarketPair] {
      let items = List.toArray(registry);
      Array.tabulate<MarketMaker.MarketPair>(
        items.size(),
        func(i : Nat) : MarketMaker.MarketPair = items[i].1,
      );
    };

    public func getPair(quoteSymbol : Text, baseSymbol : Text) : ?MarketMaker.MarketPair {
      AssocList.find<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair>(
        registry,
        (quoteSymbol, baseSymbol),
        func((x1, y1), (x2, y2)) = Text.equal(x1, x2) and Text.equal(y1, y2),
      );
    };

    func reserveQuoteCredits(c : AssocList.AssocList<Principal, Nat>) : AssocList.AssocList<Principal, Nat> {
      var credits = c;
      for ((_, pair) in List.toIter(registry)) {
        if (pair.quote_credits > 0) {
          var quoteFreeCredits = U.getByKeyOrDefault<Principal, Nat>(credits, pair.quote_principal, Principal.equal, 0);
          if (quoteFreeCredits <= pair.quote_credits) {
            pair.quote_credits := quoteFreeCredits;
            quoteFreeCredits := 0;
          } else {
            quoteFreeCredits -= pair.quote_credits;
          };
          let (upd, _) = AssocList.replace<Principal, Nat>(credits, pair.quote_principal, Principal.equal, ?quoteFreeCredits);
          credits := upd;
        };
      };
      credits;
    };

    public func setQuoteBalance(auction : AuctionWrapper.Self, quoteSymbol : Text, baseSymbol : Text, balance : Nat) : async* () {
      let ?pair = getPair(quoteSymbol, baseSymbol) else throw Error.reject("Trading pair not found");
      if (pair.quote_credits < balance) {
        var credits = await* pullCredits(auction);
        credits := reserveQuoteCredits(credits);
        let quoteCredits = U.getByKeyOrDefault<Principal, Nat>(credits, pair.quote_principal, Principal.equal, 0);
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
        pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(credits, pair.base_principal, Principal.equal, 0);
      };
    };

    public func refreshTokens(auction : AuctionWrapper.Self, default_spread_value : Float) : async* (Principal, [Principal]) {
      let quote_token = await* auction.getQuoteToken();
      let supported_tokens = await* auction.getSupportedTokens();
      let tokens_info = Tokens.getTokensInfo();

      for (token in supported_tokens.vals()) {
        if (Principal.equal(token, quote_token) == false) {
          switch (AssocList.find(tokens_info, token, Principal.equal)) {
            case (?_) {
              let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, token, Principal.equal, "Error get base token info");
              let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, quote_token, Principal.equal, "Error get quote token info");
              let pair = {
                base_principal = token;
                base_symbol = base_token_info.symbol;
                base_decimals = base_token_info.decimals;
                var base_credits = 0;
                quote_principal = quote_token;
                quote_symbol = quote_token_info.symbol;
                quote_decimals = quote_token_info.decimals;
                var quote_credits = 0;
                var spread_value = default_spread_value;
              };

              let (upd, oldValue) = AssocList.replace<(quoteSymbol : Text, baseSymbol : Text), MarketMaker.MarketPair>(
                registry,
                (pair.quote_symbol, pair.base_symbol),
                func((x1, y1), (x2, y2)) = Text.equal(x1, x2) and Text.equal(y1, y2),
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
