/// A module which contain auction definitions
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

module {
  public type CreditInfo = { total : Nat; locked : Nat; available : Nat };
  public type ManageOrdersError = {
    #placement : {
      error : {
        #ConflictingOrder : ({ #ask; #bid }, ?OrderId);
        #UnknownAsset;
        #NoCredit;
        #TooLowOrder;
      };
      index : Nat;
    };
    #UnknownPrincipal;
    #UnknownError;
    #cancellation : { error : { #UnknownAsset; #UnknownOrder }; index : Nat };
  };
  public type NotifyResult = {
    #Ok : { credit_inc : Nat; credit : Int; deposit_inc : Nat };
    #Err : {
      #NotAvailable : { message : Text };
      #CallLedgerError : { message : Text };
    };
  };
  public type OrderId = Nat;
  public type ManageOrdersResult = { #Ok : [OrderId]; #Err : ManageOrdersError };
  public type Self = actor {
    icrc84_notify : shared { token : Principal } -> async NotifyResult;
    manageOrders : shared (
        ?{
          #all : ?[Principal];
          #orders : [{ #ask : OrderId; #bid : OrderId }];
        },
        [{ #ask : (Principal, Nat, Float); #bid : (Principal, Nat, Float) }],
      ) -> async ManageOrdersResult;
    queryCredits : shared query () -> async [(Principal, CreditInfo)];
    getQuoteLedger : shared query () -> async (Principal);
    icrc84_supported_tokens: () -> async ([Principal]);
 }
}