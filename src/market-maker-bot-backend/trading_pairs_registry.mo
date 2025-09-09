import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Debug "mo:base/Debug";

import Auction "./auction_definitions";
import AuctionWrapper "./auction_wrapper";
import MarketMaker "./market_maker";
import Tokens "./tokens";
import U "./utils";

module TradingPairsRegistry {

  public type StableDataV4 = {
    registry : AssocList.AssocList<Text, MarketMaker.MarketPair>;
    quoteReserve : Nat;
    synchronizedTransactions : Nat;
  };

  public func defaultStableDataV4() : StableDataV4 = {
    registry = null;
    quoteReserve = 0;
    synchronizedTransactions = 0;
  };

  public func migrateStableDataV4(data : StableDataV3) : StableDataV4 = {
    registry = List.map<(Text, { base : MarketMaker.TokenDescription; var base_credits : Nat; var quote_credits : Nat; var spread : (value : Float, bias : Float) }), (Text, MarketMaker.MarketPair)>(
      data.registry,
      func(t, x) = (
        t,
        {
          base = x.base;
          var base_credits = x.base_credits;
          var quote_credits = x.quote_credits;
          var strategy = [(x.spread, 1.0)];
        },
      ),
    );
    quoteReserve = data.quoteReserve;
    synchronizedTransactions = data.synchronizedTransactions;
  };

  public type StableDataV3 = {
    registry : AssocList.AssocList<Text, { base : MarketMaker.TokenDescription; var base_credits : Nat; var quote_credits : Nat; var spread : (value : Float, bias : Float) }>;
    quoteReserve : Nat;
    synchronizedTransactions : Nat;
  };

  public func defaultStableDataV3() : StableDataV3 = {
    registry = null;
    quoteReserve = 0;
    synchronizedTransactions = 0;
  };

  public class TradingPairsRegistry() {

    var quote : ?MarketMaker.TokenDescription = null;

    var registry : AssocList.AssocList<Text, MarketMaker.MarketPair> = null;
    public var quoteReserve : Nat = 0;
    // amount of seen transaction history items
    var synchronizedTransactions : Nat = 0;

    public func quoteInfo() : MarketMaker.TokenDescription = U.requireMsg(quote, "Not initialized");

    public func getQuoteReserve() : Nat = quoteReserve;

    public func getTotalQuoteCredits() : Nat {
      var total = getQuoteReserve();
      for (pair in getPairs().vals()) {
        total += pair.quote_credits;
      };
      total;
    };

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

    public func getPairByLedger(ledger : Principal) : ?MarketMaker.MarketPair {
      for ((_, pair) in List.toIter(registry)) {
        if (Principal.equal(pair.base.principal, ledger)) {
          return ?pair;
        };
      };
      null;
    };

    public func initTokens(auction : AuctionWrapper.Self, default_strategy : MarketMaker.MarketPairStrategy) : async* (Principal, [Principal]) {
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
                var strategy = default_strategy;
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

    var replayTransactionHistoryLock : Bool = false;

    // replay transaction history to update quote token buckets. Returns current account revision
    public func replayTransactionHistory(auction : AuctionWrapper.Self) : async* Nat {
      assert not replayTransactionHistoryLock;
      replayTransactionHistoryLock := true;

      try {
        let pairs : [(Text, MarketMaker.MarketPair)] = List.toArray(registry);
        let basePrincipals = Array.map<(Text, MarketMaker.MarketPair), Principal>(pairs, func(_, x) = x.base.principal);
        let quoteBalances = Array.tabulateVar<Int>(pairs.size(), func(i) = pairs[i].1.quote_credits);
        let baseBalances = Array.tabulateVar<Int>(pairs.size(), func(i) = pairs[i].1.base_credits);

        var processedTransactions = synchronizedTransactions;
        var sessionNumber : Nat = 0;
        var accountRevision : Nat = 0;
        let chunkSize : Nat = 500;

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
            switch (Array.indexOf<Principal>(token, basePrincipals, Principal.equal)) {
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
        Debug.print("Transactions history replayed (" # debug_show (processedTransactions - synchronizedTransactions : Nat) # " items). Applying credits..");
        for ((_, pair) in List.toIter(registry)) {
          switch (Array.indexOf<Principal>(pair.base.principal, basePrincipals, Principal.equal)) {
            case (null) {};
            case (?tokenIdx) {
              pair.base_credits := Int.max(baseBalances[tokenIdx], 0) |> Int.abs(_);
              pair.quote_credits := Int.max(quoteBalances[tokenIdx], 0) |> Int.abs(_);
              // if removed more than available in bucket - decrement from quote reserve
              if (quoteBalances[tokenIdx] < 0) {
                quoteReserve := Int.max(quoteReserve + quoteBalances[tokenIdx], 0) |> Int.abs(_);
              };
            };
          };
        };
        synchronizedTransactions := processedTransactions;

        // refresh credits
        // calculate quote credits reserve, update values in the registry
        var creditsMap : List.List<(Principal, Nat)> = null;
        for (credit in credits.vals()) {
          creditsMap := List.push<(Principal, Nat)>((credit.0, credit.1.total), creditsMap);
        };
        var quoteFreeCredits = U.getByKeyOrDefault<Principal, Nat>(creditsMap, quoteInfo().principal, Principal.equal, 0);
        for ((_, pair) in List.toIter(registry)) {
          pair.base_credits := U.getByKeyOrDefault<Principal, Nat>(creditsMap, pair.base.principal, Principal.equal, 0);
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

        accountRevision;
      } finally {
        replayTransactionHistoryLock := false;
      };
    };

    public func share() : StableDataV4 {
      { registry; quoteReserve; synchronizedTransactions };
    };

    public func unshare(data : StableDataV4) {
      registry := data.registry;
      quoteReserve := data.quoteReserve;
      synchronizedTransactions := data.synchronizedTransactions;
    };

  };

};
