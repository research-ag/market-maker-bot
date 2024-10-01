/// A module which contain auction definitions
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

module {
  public type CreditInfo = { total : Nat; locked : Nat; available : Nat };
  public type ManageOrdersError = {
    #UnknownPrincipal;
    #cancellation : { index : Nat; error : { #UnknownAsset; #UnknownOrder } };
    #placement : {
      index : Nat;
      error : {
        #ConflictingOrder : ({ #ask; #bid }, ?OrderId);
        #NoCredit;
        #TooLowOrder;
        #UnknownAsset;
        #PriceDigitsOverflow : { maxDigits : Nat };
        #VolumeStepViolated : { baseVolumeStep : Nat };
      };
    };
    #UnknownError;
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
  type Order = {
    icrc1Ledger : Principal;
    price : Float;
    volume : Nat;
  };
  type WithdrawResult = {
    #Ok : {
      txid : Nat;
      amount : Nat;
    };
    #Err : {
      #BadFee : { expected_fee : Nat };
      #CallLedgerError : { message : Text };
      #InsufficientCredit : {};
      #AmountBelowMinimum : {};
    };
  };
  public type Self = actor {
    icrc84_notify : shared { token : Principal } -> async NotifyResult;
    icrc84_credit : shared (Principal) -> async Int;
    manageOrders : shared (
      ?{
        #all : ?[Principal];
        #orders : [{ #ask : OrderId; #bid : OrderId }];
      },
      [{ #ask : (Principal, Nat, Float); #bid : (Principal, Nat, Float) }],
    ) -> async ManageOrdersResult;
    queryCredits : shared query () -> async [(Principal, CreditInfo)];
    queryBids : shared query () -> async [(OrderId, Order)];
    queryAsks : shared query () -> async [(OrderId, Order)];
    getQuoteLedger : shared query () -> async (Principal);
    icrc84_supported_tokens : () -> async ([Principal]);
    icrc84_withdraw : ({
      to : { owner : Principal; subaccount : ?Blob };
      amount : Nat;
      token : Principal;
      expected_fee : ?Nat;
    }) -> async WithdrawResult;
    principalToSubaccount : (p : Principal) -> async ?Blob;
  };
};
