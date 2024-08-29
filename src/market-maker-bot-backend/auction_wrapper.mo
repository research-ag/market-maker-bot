/// A module which contain auction wrapper
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Prim "mo:prim";
import Auction "./auction_definitions";

module {
  public type OrderInfo = {
    amount : Nat;
    price : Float;
  };

  public class Self(auction_principal : Principal) {
    let ac : Auction.Self = actor (Principal.toText(auction_principal));

    public func getAuction() : (Auction.Self) {
      ac;
    };

    public func getQuoteToken() : async* (Principal) {
      try {
        return await ac.getQuoteLedger();
      } catch (e) {
        Debug.print(Error.message(e));
        Prim.trap("Error get quote token");
      };
    };

    public func getSupportedTokens() : async* ([Principal]) {
      try {
        return await ac.icrc84_supported_tokens();
      } catch (e) {
        Debug.print(Error.message(e));
        Prim.trap("Error get supported tokens list");
      };
    };

    public func getCredits() : async* (AssocList.AssocList<Principal, Nat>) {
      var map : AssocList.AssocList<Principal, Nat> = null;
      try {
        let credits : [(Principal, Auction.CreditInfo)] = await ac.queryCredits();

        Debug.print("Credits " # debug_show(credits));

        for (credit in credits.vals()) {
          map := AssocList.replace(map, credit.0, Principal.equal, ?credit.1.total).0;
        };
      } catch (e) {
        Debug.print(Error.message(e));
      };

      return map;
    };

    public func replaceOrders(token : Principal, bid : OrderInfo, ask : OrderInfo) : async* {
      #Ok : [Nat];
      #Err : Auction.ManageOrdersError;
    } {
      try {

        let response = await ac.manageOrders(
          ?(#all(?[token])), // cancell all orders for tokens
          [#bid(token, bid.amount, bid.price), #ask(token, ask.amount, ask.price)],
        );

        switch (response) {
          case (#Ok(success)) #Ok(success);
          case (#Err(error)) {
            switch (error) {
              case (#cancellation(_)) {
                let response = await ac.manageOrders(
                  ?(#orders([])),
                  [#bid(token, bid.amount, bid.price), #ask(token, ask.amount, ask.price)],
                );

                switch (response) {
                  case (#Ok(success)) #Ok(success);
                  case (#Err(error)) #Err(error);
                };
              };
              case (_) #Err(error);
            };
          };
        };
      } catch (_) {
        #Err(#UnknownError);
      }
    };

    public func removeOrders(token : Principal) : async* {
      #Ok;
      #Err : {
        #CancellationError;
      };
    } {
      let response = await ac.manageOrders(
        ?(#all(?[token])), // cancell all orders for tokens
        [],
      );

      switch (response) {
        case (#Ok(_)) #Ok;
        case (#Err(_)) #Err(#CancellationError);
      };
    };
  }
}