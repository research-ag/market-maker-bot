/// A module which contain some general utils
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Prim "mo:prim";

module {
  public type ExecutionError = {
    #PlacementError;
    #CancellationError;
    #UnknownPrincipal;
    #UnknownError;
    #RatesError;
    #ConflictOrderError;
    #UnknownAssetError;
    #NoCreditError;
    #TooLowOrderError;
  };

  public func getErrorMessage(error : ExecutionError) : Text {
    switch (error) {
      case (#PlacementError) "Placement order error";
      case (#CancellationError) "Cancellation order error";
      case (#UnknownPrincipal) "Unknown principal error";
      case (#UnknownError) "Unknown error";
      case (#RatesError) "No rates error";
      case (#ConflictOrderError) "Conflict order error";
      case (#UnknownAssetError) "Unknown asset error";
      case (#NoCreditError) "No credit error";
      case (#TooLowOrderError) "Too low order error";
    }
  };

  public func getByKeyOrDefault<T, K>(list : AssocList.AssocList<T, K>, key : T, equal : (T, T) -> Bool, default : K) : (K) {
    let _value : ?K = AssocList.find<T, K>(list, key, equal);
    switch (_value) {
      case (?_value) _value;
      case (null) default;
    }
  };

  public func getByKeyOrTrap<T, K>(list : AssocList.AssocList<T, K>, key : T, equal : (T, T) -> Bool, message : Text) : (K) {
    let _value : ?K = AssocList.find<T, K>(list, key, equal);
    switch (_value) {
      case (?_value) _value;
      case (null) Prim.trap(message);
    }
  };
}