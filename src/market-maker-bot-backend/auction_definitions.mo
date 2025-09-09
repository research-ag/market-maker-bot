/// A module which contain auction definitions
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

module {
  type UpperResult<Ok, Err> = { #Ok : Ok; #Err : Err };
  public type OrderId = Nat;
  public type OrderBookType = { #delayed; #immediate };
  public type EncryptedOrderBook = (Blob, Blob);
  public type Order = {
    icrc1Ledger : Principal;
    orderBookType : OrderBookType;
    price : Float;
    volume : Nat;
  };
  public type CreditInfo = {
    total : Nat;
    available : Nat;
    locked : Nat;
  };
  public type DepositHistoryItem = (timestamp : Nat64, kind : { #deposit; #withdrawal }, ledgerPrincipal : Principal, volume : Nat);
  public type TransactionHistoryItem = (timestamp : Nat64, sessionNumber : Nat, kind : { #ask; #bid }, ledgerPrincipal : Principal, volume : Nat, price : Float);
  public type PriceHistoryItem = (timestamp : Nat64, sessionNumber : Nat, ledgerPrincipal : Principal, volume : Nat, price : Float);

  public type NotifyResponse = {
    #Ok : {
      deposit_inc : Nat;
      credit_inc : Nat;
      credit : Int;
    };
    #Err : {
      #CallLedgerError : { message : Text };
      #NotAvailable : { message : Text };
    };
  };
  public type CancellationResult = (OrderId, assetId : Principal, orderBookType : OrderBookType, volume : Nat, price : Float);
  public type PlaceOrderResult = (OrderId, { #placed; #executed : [(price : Float, volume : Nat)] });
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
    #AccountRevisionMismatch;
    #UnknownPrincipal;
    #UnknownError : Text;
  };
  public type ManageOrdersError = {
    #cancellation : ManageOrdersCancellationError;
    #placement : ManageOrdersPlacementError;
  } or ManageOrdersOtherError;
  public type AuctionQuerySelection = {
    session_numbers : ?Bool;
    asks : ?Bool;
    bids : ?Bool;
    dark_order_books : ?Bool;
    credits : ?Bool;
    deposit_history : ?(limit : Nat, skip : Nat);
    transaction_history : ?(limit : Nat, skip : Nat);
    price_history : ?(limit : Nat, skip : Nat, skipEmpty : Bool);
    immediate_price_history : ?(limit : Nat, skip : Nat);
    reversed_history : ?Bool;
    last_prices : ?Bool;
  };
  public let EMPTY_QUERY : AuctionQuerySelection = {
    session_numbers = null;
    asks = null;
    bids = null;
    dark_order_books = null;
    credits = null;
    deposit_history = null;
    transaction_history = null;
    price_history = null;
    immediate_price_history = null;
    reversed_history = null;
    last_prices = null;
  };
  public type AuctionQueryResponse = {
    session_numbers : [(Principal, Nat)];
    asks : [(OrderId, Order)];
    bids : [(OrderId, Order)];
    dark_order_books : [(Principal, EncryptedOrderBook)];
    credits : [(Principal, CreditInfo)];
    deposit_history : [DepositHistoryItem];
    transaction_history : [TransactionHistoryItem];
    price_history : [PriceHistoryItem];
    immediate_price_history : [PriceHistoryItem];
    last_prices : [PriceHistoryItem];
    points : Nat;
    account_revision : Nat;
  };
  public type WithdrawArgs = {
    to : { owner : Principal; subaccount : ?Blob };
    amount : Nat;
    token : Principal;
    expected_fee : ?Nat;
  };
  public type WithdrawResponse = {
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
    icrc84_notify : shared { token : Principal } -> async NotifyResponse;
    manageOrders : shared (
      cancellations : ?{
        #all : ?[Principal];
        #orders : [{ #ask : OrderId; #bid : OrderId }];
      },
      placements : [{
        #ask : (token : Principal, orderBookType : OrderBookType, volume : Nat, price : Float);
        #bid : (token : Principal, orderBookType : OrderBookType, volume : Nat, price : Float);
      }],
      expectedAccountRevision : ?Nat,
    ) -> async UpperResult<([CancellationResult], [PlaceOrderResult]), ManageOrdersError>;
    auction_query : shared query (tokens : [Principal], selection : AuctionQuerySelection) -> async AuctionQueryResponse;
    getQuoteLedger : shared query () -> async (Principal);
    icrc84_supported_tokens : () -> async ([Principal]);
    icrc84_withdraw : (WithdrawArgs) -> async WithdrawResponse;
  };
};
