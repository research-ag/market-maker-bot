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
  type PriceHistoryItem = (timestamp : Nat64, sessionNumber : Nat, ledgerPrincipal : Principal, volume : Nat, price : Float);
  type DepositHistoryItem = (timestamp : Nat64, kind : { #deposit; #withdrawal; #withdrawalRollback }, ledgerPrincipal : Principal, volume : Nat);
  type TransactionHistoryItem = (timestamp : Nat64, sessionNumber : Nat, kind : { #ask; #bid }, ledgerPrincipal : Principal, volume : Nat, price : Float);
  public type AuctionQuerySelection = {
    session_numbers : ?Bool;
    asks : ?Bool;
    bids : ?Bool;
    credits : ?Bool;
    deposit_history : ?(limit : Nat, skip : Nat);
    transaction_history : ?(limit : Nat, skip : Nat);
    price_history : ?(limit : Nat, skip : Nat, skipEmpty : Bool);
    reversed_history : ?Bool;
    last_prices : ?Bool;
  };
  public let EMPTY_QUERY : AuctionQuerySelection = {
    session_numbers = null;
    asks = null;
    bids = null;
    credits = null;
    deposit_history = null;
    transaction_history = null;
    price_history = null;
    reversed_history = null;
    last_prices = null;
  };
  public type AuctionQueryResponse = {
    session_numbers : [(Principal, Nat)];
    asks : [(OrderId, Order)];
    bids : [(OrderId, Order)];
    credits : [(Principal, CreditInfo)];
    deposit_history : [DepositHistoryItem];
    transaction_history : [TransactionHistoryItem];
    price_history : [PriceHistoryItem];
    last_prices : [PriceHistoryItem];
    points : Nat;
  };
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
    auction_query : shared query (tokens : [Principal], selection : AuctionQuerySelection) -> async AuctionQueryResponse;
    getQuoteLedger : shared query () -> async (Principal);
    icrc84_supported_tokens : () -> async ([Principal]);
    icrc84_withdraw : ({
      to : { owner : Principal; subaccount : ?Blob };
      amount : Nat;
      token : Principal;
      expected_fee : ?Nat;
    }) -> async WithdrawResult;
  };
};
