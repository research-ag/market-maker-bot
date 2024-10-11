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
import Prim "mo:prim";
import Principal "mo:base/Principal";

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

    public func getCredit(token : Principal) : async* Int {
      await ac.icrc84_credit(token);
    };

    public func getCredits() : async* (AssocList.AssocList<Principal, Nat>) {
      var map : List.List<(Principal, Nat)> = null;
      try {
        let credits : [(Principal, Auction.CreditInfo, Nat)] = await ac.queryCredits();

        Debug.print("Credits " # debug_show (credits));

        for (credit in credits.vals()) {
          map := List.push<(Principal, Nat)>((credit.0, credit.1.total), map);
        };
      } catch (e) {
        Debug.print(Error.message(e));
      };

      return map;
    };

    public func replaceOrders(token : Principal, bid : OrderInfo, ask : OrderInfo) : async* {
      #Ok : (orderIds : [Nat], quoteBalanceDelta : Int);
      #Err : Auction.ManageOrdersError;
    } {
      let placeAsk = ask.amount > 0;
      let placeBid = Int.abs(Float.toInt(Float.ceil(bid.price * Float.fromInt(bid.amount)))) >= 5_000;

      let placements : [{
        #ask : (Principal, Nat, Float);
        #bid : (Principal, Nat, Float);
      }] = switch (placeBid, placeAsk) {
        case (false, false) [];
        case (false, _) [#ask(token, ask.amount, ask.price)];
        case (_, false) [#bid(token, bid.amount, bid.price)];
        case (_) [#bid(token, bid.amount, bid.price), #ask(token, ask.amount, ask.price)];
      };
      try {
        let (bidQuoteDelta, sessionNumber) : (Int, ?Nat) = if (placeBid) {
          let (oldBids, sessionNumber) = await ac.queryTokenBids(token);
          let oldBidQuoteVolume : Int = if (oldBids.size() > 0) {
            oldBids[0].1.price * Float.fromInt(oldBids[0].1.volume) |> Float.toInt(Float.ceil(_));
          } else {
            0;
          };
          let newBidQuoteVolume : Int = bid.price * Float.fromInt(bid.amount) |> Float.toInt(Float.ceil(_));
          (oldBidQuoteVolume - newBidQuoteVolume, ?sessionNumber);
        } else {
          (0, null);
        };
        let res = await ac.manageOrders(
          ?(#all(?[token])), // cancel all orders for tokens
          placements,
          sessionNumber,
        );
        switch (res) {
          case (#Ok orderIds) #Ok(orderIds, bidQuoteDelta);
          case (#Err x) #Err(x);
        };
      } catch (_) {
        #Err(#UnknownError);
      };
    };

    public func removeOrders(tokens : [Principal]) : async* {
      #Ok;
      #Err : {
        #CancellationError;
        #UnknownError;
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
      } catch (e) {
        Debug.print(Error.message(e));
        #Err(#UnknownError);
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
