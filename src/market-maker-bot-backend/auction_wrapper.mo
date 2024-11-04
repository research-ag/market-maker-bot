/// A module which contain auction wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import List "mo:base/List";
import Option "mo:base/Option";
import Prim "mo:prim";
import Principal "mo:base/Principal";

import Vec "mo:vector";

import Auction "./auction_definitions";

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
      let (credit, _) = await ac.queryCredit(token);
      credit.total;
    };

    // returns total credits (available + locked)
    public func getCredits() : async* (AssocList.AssocList<Principal, Nat>, Nat) {
      var map : List.List<(Principal, Nat)> = null;
      var sessionNumber : ?Nat = null;
      try {
        let credits : [(Principal, Auction.CreditInfo, Nat)] = await ac.queryCredits();

        Debug.print("Credits " # debug_show (credits));

        for (credit in credits.vals()) {
          map := List.push<(Principal, Nat)>((credit.0, credit.1.total), map);
          switch (sessionNumber) {
            case (?sn) assert credit.2 == sn;
            case (null) sessionNumber := ?credit.2;
          };
        };
      } catch (e) {
        Debug.print(Error.message(e));
      };

      (map, Option.get(sessionNumber, 0));
    };

    public func replaceOrders(orders : [(token : Principal, bid : OrderInfo, ask : OrderInfo)], sessionNumber : ?Nat) : async* {
      #Ok : [Nat];
      #Err : Auction.ManageOrdersError;
    } {
      let placements : Vec.Vector<{ #ask : (Principal, Nat, Float); #bid : (Principal, Nat, Float) }> = Vec.new();
      let cancellations : Vec.Vector<Principal> = Vec.new();

      for ((token, bid, ask) in orders.vals()) {
        Vec.add(cancellations, token);
        if (ask.amount > 0) {
          Vec.add(placements, #ask(token, ask.amount, ask.price));
        };
        if (Int.abs(Float.toInt(Float.ceil(bid.price * Float.fromInt(bid.amount)))) >= 5_000) {
          Vec.add(placements, #bid(token, bid.amount, bid.price));
        };
      };
      try {
        await ac.manageOrders(?(#all(?Vec.toArray(cancellations))), Vec.toArray(placements), sessionNumber);
      } catch (err) {
        #Err(#UnknownError(Error.message(err)));
      };
    };

    public func removeOrders(tokens : [Principal]) : async* {
      #Ok;
      #Err : {
        #CancellationError;
        #UnknownError : Text;
      };
    } {
      try {
        let response = await ac.manageOrders(
          ?(#all(?tokens)), // cancel all orders for tokens
          [],
          null,
        );

        switch (response) {
          case (#Ok(_)) #Ok;
          case (#Err(_)) #Err(#CancellationError);
        };
      } catch (err) {
        Debug.print(Error.message(err));
        #Err(#UnknownError(Error.message(err)));
      };
    };

    public func notify(token : Principal) : async* {
      #Ok;
      #Err;
    } {
      try {
        let response = await ac.icrc84_notify({ token });

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
