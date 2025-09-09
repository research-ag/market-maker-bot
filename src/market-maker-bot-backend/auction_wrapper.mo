/// A module which contain auction wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Array "mo:base/Array";

import Vec "mo:vector";

import Auction "./auction_definitions";
import U "./utils";

module {
  public type OrderInfo = {
    amount : Nat;
    price : Float;
  };

  public class Self(auction_principal : Principal) {
    let ac : Auction.Self = actor (Principal.toText(auction_principal));

    public func getAuction() : (Auction.Self) = ac;

    public func getQuoteToken() : async* (Principal) {
      try {
        return await ac.getQuoteLedger();
      } catch (e) {
        Debug.print(Error.message(e));
        /// TODO remove the trap and return an error to decide what to do in high order function
        /// put callback to constructor and call it here
        Prim.trap("Error get quote token");
      };
    };

    public func getSupportedTokens() : async* ([Principal]) {
      try {
        return await ac.icrc84_supported_tokens();
      } catch (e) {
        Debug.print(Error.message(e));
        /// TODO remove the trap and return an error to decide what to do in high order function
        Prim.trap("Error get supported tokens list");
      };
    };

    // returns total credit (available + locked)
    public func getCredit(token : Principal) : async* Nat {
      let { credits } = await ac.auction_query(
        [token],
        { Auction.EMPTY_QUERY with credits = ?true },
      );
      switch (credits.size()) {
        case (0) 0;
        case (_) credits[0].1.total;
      };
    };

    public func replaceOrders(orders : [(token : Principal, bids : [OrderInfo], asks : [OrderInfo])], sessionNumber : ?Nat) : async* {
      #Ok : ([Auction.CancellationResult], [Auction.PlaceOrderResult]);
      #Err : {
        #cancellation : Auction.ManageOrdersCancellationError;
        #placement : (argIndex : Nat, failedAsk : ?OrderInfo, failedBid : ?OrderInfo, error : Auction.ManageOrdersPlacementError);
      } or Auction.ManageOrdersOtherError;
    } {
      let placements : Vec.Vector<{ #ask : (Principal, Auction.OrderBookType, Nat, Float); #bid : (Principal, Auction.OrderBookType, Nat, Float) }> = Vec.new();
      for ((token, bids, asks) in orders.vals()) {
        for (ask in asks.vals()) {
          if (ask.amount > 0) {
            Vec.add(placements, #ask(token, #delayed, ask.amount, ask.price));
          };
        };
        for (bid in bids.vals()) {
          if (Int.abs(Float.toInt(Float.ceil(bid.price * Float.fromInt(bid.amount)))) >= 5_000) {
            Vec.add(placements, #bid(token, #delayed, bid.amount, bid.price));
          };
        };
      };
      try {
        let res = await ac.manageOrders(?(#all(null)), Vec.toArray(placements), sessionNumber);
        switch (res) {
          case (#Ok x) #Ok(x);
          case (#Err err) switch (err) {
            case (#placement(e)) {
              let argIndex = func(token : Principal) : Nat = U.require(Array.indexOf<(Principal, [OrderInfo], [OrderInfo])>((token, [], []), orders, func(a, b) = a.0 == b.0));
              switch (Vec.get(placements, e.index)) {
                case (#ask(token, _, amount, price)) #Err(#placement(argIndex(token), ?{ amount; price }, null, e));
                case (#bid(token, _, amount, price)) #Err(#placement(argIndex(token), null, ?{ amount; price }, e));
              };
            };
            case (#cancellation(e)) #Err(#cancellation(e));
            case (#AccountRevisionMismatch(x)) #Err(#AccountRevisionMismatch(x));
            case (#UnknownPrincipal(x)) #Err(#UnknownPrincipal(x));
            case (#UnknownError(x)) #Err(#UnknownError(x));
          };
        };
      } catch (err) #Err(#UnknownError(Error.message(err)));
    };

    public func removeOrders() : async* {
      #Ok;
      #Err : {
        #CancellationError;
        #UnknownError : Text;
      };
    } {
      try {
        let response = await ac.manageOrders(?(#all(null)), [], null);
        switch (response) {
          case (#Ok(_)) #Ok;
          case (#Err(_)) #Err(#CancellationError);
        };
      } catch (err) {
        Debug.print(Error.message(err));
        #Err(#UnknownError(Error.message(err)));
      };
    };

    public func notify(tokens : [Principal]) : async* [{ #Ok; #Err }] {
      let calls : [var ?(async Auction.NotifyResponse)] = Array.init(tokens.size(), null);
      for (i in tokens.keys()) {
        calls[i] := ?ac.icrc84_notify({ token = tokens[i] });
      };
      let res : [var { #Ok; #Err }] = Array.init(tokens.size(), #Err);
      for (i in calls.keys()) {
        res[i] := switch (calls[i]) {
          case (null) #Err;
          case (?call) {
            try {
              let response = await call;
              switch (response) {
                case (#Ok(_)) #Ok;
                case (#Err(_)) #Err;
              };
            } catch (e) {
              Debug.print(Error.message(e));
              #Err;
            };
          };
        };
      };
      Array.freeze(res);
    };
  };
};
