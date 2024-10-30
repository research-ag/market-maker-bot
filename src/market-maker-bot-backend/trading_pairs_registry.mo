import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Debug "mo:base/Debug";

import AuctionWrapper "./auction_wrapper";
import MarketMaker "./market_maker";
import Tokens "./tokens";
import U "./utils";

module TradingPairsRegistry {

  public type StableDataV2 = {
    registry : AssocList.AssocList<Text, MarketMaker.MarketPair>;
    quoteReserve : Nat;
    synchronizedTransactions : Nat;
  };

  public func defaultStableDataV2() : StableDataV1 = {
    registry = null;
    quoteReserve = 0;
    synchronizedTransactions = 0;
  };

  public func migrateStableDataV2(data : StableDataV1) : StableDataV2 = {
    registry = data.registry;
    quoteReserve = data.quoteReserve;
    synchronizedTransactions = 0;
  };

  public type StableDataV1 = {
    registry : AssocList.AssocList<Text, MarketMaker.MarketPair>;
    quoteReserve : Nat;
  };

  public func defaultStableDataV1() : StableDataV1 = {
    registry = null;
    quoteReserve = 0;
  };

  public class TradingPairsRegistry() {

    var quote : ?MarketMaker.TokenDescription = null;

    var registry : AssocList.AssocList<Text, MarketMaker.MarketPair> = null;
    var quoteReserve : Nat = 0;
    // amount of seen transaction history items
    var synchronizedTransactions : Nat = 0;

    public func quoteInfo() : MarketMaker.TokenDescription = U.requireMsg(quote, "Not initialized");

    public func getQuoteReserve() : Nat = quoteReserve;

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

    public func initTokens(auction : AuctionWrapper.Self, default_spread_value : Float) : async* (Principal, [Principal]) {
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
              let pair : MarketMaker.MarketPair = {
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

    public func setQuoteBalance(auction : AuctionWrapper.Self, baseSymbol : Text, balance : { #set : Nat; #inc : Nat; #dec : Nat }) : async* Nat {
      let ?pair = getPair(baseSymbol) else throw Error.reject("Trading pair not found");
      var balanceInc : Int = switch (balance) {
        case (#set x) {
          ignore await* replayTransactionHistory(auction);
          x - pair.quote_credits;
        };
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

    // replay transaction history to update quote token buckets. Returns current session number
    public func replayTransactionHistory(auction : AuctionWrapper.Self) : async* Nat {
      let pairs : [(Text, MarketMaker.MarketPair)] = List.toArray(registry);
      let basePrincipals = Array.map<(Text, MarketMaker.MarketPair), Principal>(pairs, func(_, x) = x.base.principal);
      let balances = Array.tabulateVar<Int>(pairs.size(), func(i) = pairs[i].1.quote_credits);

      var processedTransactions = synchronizedTransactions;
      var sessionNumber : Nat = 0;
      let chunkSize : Nat = 500;
      label l while (true) {
        Debug.print("Replaying transactions history from " # debug_show processedTransactions # "...");
        let (historyChunk, sn, auctionInProgress) = await auction.getAuction().queryTransactionHistoryForward(null, chunkSize, processedTransactions);
        sessionNumber := sn;
        for ((_, _, kind, token, volume, price) in historyChunk.vals()) {
          switch (Array.indexOf<Principal>(token, basePrincipals, Principal.equal)) {
            case (null) {};
            case (?tokenIdx) {
              switch (kind) {
                case (#bid) balances[tokenIdx] -= (price * Float.fromInt(volume) |> Int.abs(Float.toInt(Float.ceil(_))));
                case (#ask) balances[tokenIdx] += (price * Float.fromInt(volume) |> Int.abs(Float.toInt(Float.floor(_))));
              };
            };
          };
        };
        processedTransactions += historyChunk.size();
        if (historyChunk.size() < chunkSize and not auctionInProgress) break l;
      };
      Debug.print("Transactions history replayed. Applying credits..");
      for ((_, pair) in List.toIter(registry)) {
        switch (Array.indexOf<Principal>(pair.base.principal, basePrincipals, Principal.equal)) {
          case (null) {};
          case (?tokenIdx) {
            let newBalance = Int.max(balances[tokenIdx], 0) |> Int.abs(_);
            let delta : Int = pair.quote_credits - newBalance;
            pair.quote_credits := newBalance;
            quoteReserve := Int.max(quoteReserve + delta, 0) |> Int.abs(_);
          };
        };
      };
      synchronizedTransactions := processedTransactions;
      sessionNumber;
    };

    // pulls credits from the auction
    public func refreshCredits(auction : AuctionWrapper.Self) : async* Nat {
      let (credits, sessionNumber) = await* auction.getCredits();
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
      sessionNumber;
    };

    public func share() : StableDataV2 {
      { registry; quoteReserve; synchronizedTransactions };
    };

    public func unshare(data : StableDataV2) {
      registry := data.registry;
      quoteReserve := data.quoteReserve;
      synchronizedTransactions := data.synchronizedTransactions;
    };

  };

};
