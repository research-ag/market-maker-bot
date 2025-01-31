/// A module which contain auction definitions
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

module {
  public type CreditInfo = { total : Nat; locked : Nat; available : Nat };
  public type ManageOrdersCancellationError = {
    index : Nat;
    error : {
      #UnknownAsset;
      #UnknownOrder;
    };
  };
  public type ManageOrdersPlacementError = {
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
  public type ManageOrdersOtherError = {
    #SessionNumberMismatch : Principal;
    #UnknownPrincipal;
    #UnknownError : Text;
  };
  public type ManageOrdersError = {
    #cancellation : ManageOrdersCancellationError;
    #placement : ManageOrdersPlacementError;
  } or ManageOrdersOtherError;
  public type NotifyResult = {
    #Ok : { credit_inc : Nat; credit : Int; deposit_inc : Nat };
    #Err : {
      #NotAvailable : { message : Text };
      #CallLedgerError : { message : Text };
    };
  };
  public type OrderId = Nat;
  public type CancellationResult = (OrderId, assetId : Principal, volume : Nat, price : Float);
  public type ManageOrdersResult = {
    #Ok : ([CancellationResult], [OrderId]);
    #Err : ManageOrdersError;
  };
  public type WithdrawResult = {
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
  public type Order = {
    icrc1Ledger : Principal;
    price : Float;
    volume : Nat;
  };
  public type TransactionHistoryItem = (timestamp : Nat64, sessionNumber : Nat, kind : { #ask; #bid }, ledgerPrincipal : Principal, volume : Nat, price : Float);
  public type Self = actor {
    icrc84_notify : shared { token : Principal } -> async NotifyResult;
    manageOrders : shared (
      ?{
        #all : ?[Principal];
        #orders : [{ #ask : OrderId; #bid : OrderId }];
      },
      [{ #ask : (Principal, Nat, Float); #bid : (Principal, Nat, Float) }],
      ?Nat,
    ) -> async ManageOrdersResult;
    queryCredit : shared query (Principal) -> async (CreditInfo, Nat);
    queryCredits : shared query () -> async [(Principal, CreditInfo, Nat)];
    getQuoteLedger : shared query () -> async (Principal);
    icrc84_supported_tokens : () -> async ([Principal]);
    icrc84_withdraw : ({
      to : { owner : Principal; subaccount : ?Blob };
      amount : Nat;
      token : Principal;
      expected_fee : ?Nat;
    }) -> async WithdrawResult;
    queryTransactionHistoryForward : query (token : ?Principal, limit : Nat, skip : Nat) -> async (history : [TransactionHistoryItem], sessionNumber : Nat, auctionInProgress : Bool);
  };
};
