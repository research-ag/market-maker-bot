// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type CancelOrderError = { #UnknownOrder; #UnknownPrincipal };
  public type CreditInfo = { total : Nat; locked : Nat; available : Nat };
  public type DepositResult = {
    #Ok : { credit_inc : Nat; txid : Nat; credit : Int };
    #Err : {
      #TransferError : { message : Text };
      #AmountBelowMinimum : {};
      #CallLedgerError : { message : Text };
      #BadFee : { expected_fee : Nat };
    };
  };
  public type HttpRequest = {
    url : Text;
    method : Text;
    body : Blob;
    headers : [(Text, Text)];
  };
  public type HttpResponse = {
    body : Blob;
    headers : [(Text, Text)];
    status_code : Nat16;
  };
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
    #cancellation : { error : { #UnknownAsset; #UnknownOrder }; index : Nat };
  };
  public type NotifyResult = {
    #Ok : { credit_inc : Nat; credit : Int; deposit_inc : Nat };
    #Err : {
      #NotAvailable : { message : Text };
      #CallLedgerError : { message : Text };
    };
  };
  public type Order = { icrc1Ledger : Principal; volume : Nat; price : Float };
  public type OrderId = Nat;
  public type PlaceOrderError = {
    #ConflictingOrder : ({ #ask; #bid }, ?OrderId);
    #UnknownAsset;
    #NoCredit;
    #UnknownPrincipal;
    #TooLowOrder;
  };
  public type PriceHistoryItem = (Nat64, Nat, Principal, Nat, Float);
  public type RegisterAssetError = { #AlreadyRegistered : Nat };
  public type ReplaceOrderError = {
    #ConflictingOrder : ({ #ask; #bid }, ?OrderId);
    #UnknownAsset;
    #UnknownOrder;
    #NoCredit;
    #UnknownPrincipal;
    #TooLowOrder;
  };
  public type TokenInfo = {
    allowance_fee : Nat;
    withdrawal_fee : Nat;
    deposit_fee : Nat;
  };
  public type TransactionHistoryItem = (
    Nat64,
    Nat,
    { #ask; #bid },
    Principal,
    Nat,
    Float,
  );
  public type UpperResult = { #Ok : OrderId; #Err : ReplaceOrderError };
  public type UpperResult_1 = { #Ok : Nat; #Err : RegisterAssetError };
  public type UpperResult_2 = { #Ok : OrderId; #Err : PlaceOrderError };
  public type UpperResult_3 = { #Ok : [OrderId]; #Err : ManageOrdersError };
  public type UpperResult_4 = { #Ok; #Err : CancelOrderError };
  public type WithdrawResult = {
    #Ok : { txid : Nat; amount : Nat };
    #Err : {
      #AmountBelowMinimum : {};
      #InsufficientCredit : {};
      #CallLedgerError : { message : Text };
      #BadFee : { expected_fee : Nat };
    };
  };
  public type Self = actor {
    addAdmin : shared Principal -> async ();
    cancelAsks : shared [OrderId] -> async [UpperResult_4];
    cancelBids : shared [OrderId] -> async [UpperResult_4];
    debugLastBidProcessingInstructions : shared query () -> async Nat64;
    getTrustedLedger : shared query () -> async Principal;
    http_request : shared query HttpRequest -> async HttpResponse;
    icrc84_all_credits : shared query () -> async [(Principal, Int)];
    icrc84_credit : shared query Principal -> async Int;
    icrc84_deposit : shared {
        token : Principal;
        from : { owner : Principal; subaccount : ?Blob };
        amount : Nat;
        expected_fee : ?Nat;
      } -> async DepositResult;
    icrc84_notify : shared { token : Principal } -> async NotifyResult;
    icrc84_supported_tokens : shared query () -> async [Principal];
    icrc84_token_info : shared query Principal -> async TokenInfo;
    icrc84_trackedDeposit : shared query Principal -> async {
        #Ok : Nat;
        #Err : { #NotAvailable : { message : Text } };
      };
    icrc84_withdraw : shared {
        token : Principal;
        to_subaccount : ?Blob;
        amount : Nat;
        expected_fee : ?Nat;
      } -> async WithdrawResult;
    init : shared () -> async ();
    listAdmins : shared query () -> async [Principal];
    manageOrders : shared (
        ?{
          #all : ?[Principal];
          #orders : [{ #ask : OrderId; #bid : OrderId }];
        },
        [{ #ask : (Principal, Nat, Float); #bid : (Principal, Nat, Float) }],
      ) -> async UpperResult_3;
    minimumOrder : shared query () -> async Nat;
    placeAsks : shared [(Principal, Nat, Float)] -> async [UpperResult_2];
    placeBids : shared [(Principal, Nat, Float)] -> async [UpperResult_2];
    principalToSubaccount : shared query Principal -> async ?Blob;
    queryAsks : shared query () -> async [(OrderId, Order)];
    queryBids : shared query () -> async [(OrderId, Order)];
    queryCredits : shared query () -> async [(Principal, CreditInfo)];
    queryPriceHistory : shared query (?Principal, Nat, Nat) -> async [
        PriceHistoryItem
      ];
    queryTokenAsks : shared query Principal -> async [(OrderId, Order)];
    queryTokenBids : shared query Principal -> async [(OrderId, Order)];
    queryTokenHandlerState : shared query Principal -> async {
        balance : {
          deposited : Nat;
          underway : Nat;
          queued : Nat;
          consolidated : Nat;
        };
        flow : { withdrawn : Nat; consolidated : Nat };
        credit : { total : Int; pool : Int };
        users : { queued : Nat };
      };
    queryTransactionHistory : shared query (?Principal, Nat, Nat) -> async [
        TransactionHistoryItem
      ];
    registerAsset : shared (Principal, Nat) -> async UpperResult_1;
    removeAdmin : shared Principal -> async ();
    replaceAsk : shared (OrderId, Nat, Float) -> async UpperResult;
    replaceBid : shared (OrderId, Nat, Float) -> async UpperResult;
    runAuctionImmediately : shared () -> async ();
    sessionRemainingTime : shared query () -> async Nat;
    sessionsCounter : shared query () -> async Nat;
  }
}