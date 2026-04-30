import Array "mo:core/Array";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Float "mo:core/Float";
import Int "mo:core/Int";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";

import Auction "auction_definitions";
import AuctionWrapper "auction_wrapper";
import MarketMaker "market_maker";
import Tokens "tokens";
import U "utils";

module TradingPairsRegistry {

  public type TradingPairsRegistry = {
    registry : Map.Map<Text, MarketMaker.MarketPair>;
    var quote : ?MarketMaker.TokenDescription;
    var quoteReserve : Nat;
    var synchronizedTransactions : Nat;
    var replayTransactionHistoryLock : Bool;
  };

  public func new() : TradingPairsRegistry = {
    registry = Map.empty();
    var quote = null;
    var quoteReserve = 0;
    var synchronizedTransactions = 0;
    var replayTransactionHistoryLock = false;
  };

  public func quoteInfo(self : TradingPairsRegistry) : MarketMaker.TokenDescription = U.requireMsg(self.quote, "Not initialized");

  public func getQuoteReserve(self : TradingPairsRegistry) : Nat = self.quoteReserve;

  public func getTotalQuoteCredits(self : TradingPairsRegistry) : Nat {
    var total = self.quoteReserve;
    for (pair in getPairs(self).vals()) {
      total += pair.quote_credits;
    };
    total;
  };

  public func nPairs(self : TradingPairsRegistry) : Nat = self.registry.size();

  public func getPairs(self : TradingPairsRegistry) : [MarketMaker.MarketPair] {
    self.registry.toArray().map<(Text, MarketMaker.MarketPair), MarketMaker.MarketPair>(func(_, pair) = pair);
  };

  public func getPair(self : TradingPairsRegistry, baseSymbol : Text) : ?MarketMaker.MarketPair {
    self.registry.get(Text.compare, baseSymbol);
  };

  public func getPairByLedger(self : TradingPairsRegistry, ledger : Principal) : ?MarketMaker.MarketPair {
    for (pair in self.registry.values()) {
      if (pair.base.principal.equal(ledger)) {
        return ?pair;
      };
    };
    null;
  };

  public func initTokens(self : TradingPairsRegistry, auction : AuctionWrapper.Self, default_strategy : MarketMaker.MarketPairStrategy) : async* (Principal, [Principal]) {
    let quote_token = await* auction.getQuoteToken();
    let supported_tokens = await* auction.getSupportedTokens();
    let tokens_info = Tokens.getTokensInfo();
    let quote_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, quote_token, Principal.compare, "Error get quote token info");
    self.quote := ?{
      principal = quote_token;
      symbol = quote_token_info.symbol;
      decimals = quote_token_info.decimals;
    };

    for (token in supported_tokens.vals()) {
      if (not Principal.equal(token, quote_token)) {
        switch (tokens_info.get(Principal.compare, token)) {
          case (?_) {
            let base_token_info = U.getByKeyOrTrap<Principal, Tokens.TokenInfo>(tokens_info, token, Principal.compare, "Error get base token info");
            if (not self.registry.containsKey(Text.compare, base_token_info.symbol)) {
              let pair : MarketMaker.MarketPair = {
                base = {
                  principal = token;
                  symbol = base_token_info.symbol;
                  decimals = base_token_info.decimals;
                };
                var base_credits = 0;
                var quote_credits = 0;
                var strategy = default_strategy;
              };
              self.registry.add(Text.compare, base_token_info.symbol, pair);
            };
          };
          case (_) {};
        };
      };
    };
    (quote_token, supported_tokens);
  };

  public func setQuoteBalance(self : TradingPairsRegistry, auction : AuctionWrapper.Self, baseSymbol : Text, balance : { #set : Nat; #inc : Nat; #dec : Nat }) : async* Nat {
    let ?pair = getPair(self, baseSymbol) else throw Error.reject("Trading pair not found");
    let balanceInc : Int = switch (balance) {
      case (#set x) {
        ignore await* replayTransactionHistory(self, auction);
        x - pair.quote_credits;
      };
      case (#inc x) x;
      case (#dec x) Int.max(-pair.quote_credits, -x);
    };
    if (balanceInc > 0 and self.quoteReserve < balanceInc) {
      throw Error.reject("Insufficient quote token balance");
    };
    pair.quote_credits := Int.abs(pair.quote_credits + balanceInc);
    self.quoteReserve := Int.abs(self.quoteReserve - balanceInc);
    pair.quote_credits;
  };

  // replay transaction history to update quote token buckets. Returns current account revision
  public func replayTransactionHistory(self : TradingPairsRegistry, auction : AuctionWrapper.Self) : async* Nat {
    assert not self.replayTransactionHistoryLock;
    self.replayTransactionHistoryLock := true;

    try {
      let pairs : [(Text, MarketMaker.MarketPair)] = self.registry.toArray();
      let basePrincipals = Array.map<(Text, MarketMaker.MarketPair), Principal>(pairs, func(_, x) = x.base.principal);
      let quoteBalances = VarArray.tabulate<Int>(pairs.size(), func(i) = pairs[i].1.quote_credits);
      let baseBalances = VarArray.tabulate<Int>(pairs.size(), func(i) = pairs[i].1.base_credits);

      var processedTransactions = self.synchronizedTransactions;
      var sessionNumber : Nat = 0;
      var accountRevision : Nat = 0;
      let chunkSize : Nat = 5000;

      var credits : [(Principal, Auction.CreditInfo)] = [];
      label l while (true) {
        Debug.print("Replaying transactions history from " # debug_show processedTransactions # "...");
        let {
          credits = c;
          session_numbers;
          transaction_history = historyChunk;
          account_revision;
        } = await auction.getAuction().auction_query(
          [],
          {
            Auction.EMPTY_QUERY with
            credits = ?true;
            session_numbers = ?true;
            transaction_history = ?(chunkSize, processedTransactions);
            reversed_history = ?false;
          },
        );
        credits := c;
        accountRevision := account_revision;
        var auctionInProgress = false;
        for (i in session_numbers.keys()) {
          if (i == 0) {
            sessionNumber := session_numbers[i].1;
          } else if (session_numbers[i].1 != sessionNumber) {
            auctionInProgress := true;
            sessionNumber := Nat.min(sessionNumber, session_numbers[i].1);
          };
        };
        for ((_, _, kind, token, volume, price) in historyChunk.vals()) {
          switch (Array.indexOf<Principal>(basePrincipals, Principal.equal, token)) {
            case (null) {};
            case (?tokenIdx) {
              switch (kind) {
                case (#bid) {
                  quoteBalances[tokenIdx] -= (price * Float.fromInt(volume) |> Int.abs(Float.toInt(Float.ceil(_))));
                  baseBalances[tokenIdx] += volume;
                };
                case (#ask) {
                  quoteBalances[tokenIdx] += (price * Float.fromInt(volume) |> Int.abs(Float.toInt(Float.floor(_))));
                  baseBalances[tokenIdx] -= volume;
                };
              };
            };
          };
        };
        processedTransactions += historyChunk.size();
        if (historyChunk.size() < chunkSize and not auctionInProgress) break l;
      };
      Debug.print("Transactions history replayed (" # debug_show (processedTransactions - self.synchronizedTransactions : Nat) # " items). Applying credits..");
      for (pair in Map.values(self.registry)) {
        switch (Array.indexOf<Principal>(basePrincipals, Principal.equal, pair.base.principal)) {
          case (null) {};
          case (?tokenIdx) {
            pair.base_credits := Int.max(baseBalances[tokenIdx], 0) |> Int.abs(_);
            pair.quote_credits := Int.max(quoteBalances[tokenIdx], 0) |> Int.abs(_);
            // if removed more than available in bucket - decrement from quote reserve
            if (quoteBalances[tokenIdx] < 0) {
              self.quoteReserve := Int.max(self.quoteReserve + quoteBalances[tokenIdx], 0) |> Int.abs(_);
            };
          };
        };
      };
      self.synchronizedTransactions := processedTransactions;

      // refresh credits
      // calculate quote credits reserve, update values in the registry
      let creditsMap : Map.Map<Principal, Nat> = Map.empty();
      for (credit in credits.vals()) {
        Map.add(creditsMap, Principal.compare, credit.0, credit.1.total);
      };
      var quoteFreeCredits = U.getByKeyOrDefault<Principal, Nat>(creditsMap, quoteInfo(self).principal, Principal.compare, 0);
      for (pair in Map.values(self.registry)) {
        pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(creditsMap, pair.base.principal, Principal.compare, 0);
        if (pair.quote_credits > 0) {
          if (quoteFreeCredits <= pair.quote_credits) {
            pair.quote_credits := quoteFreeCredits;
            quoteFreeCredits := 0;
          } else {
            quoteFreeCredits -= pair.quote_credits;
          };
        };
      };
      self.quoteReserve := quoteFreeCredits;

      accountRevision;
    } finally {
      self.replayTransactionHistoryLock := false;
    };
  };

};
