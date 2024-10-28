/// A module which contain some general utils
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Prim "mo:prim";
import Principal "mo:base/Principal";

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
    #VolumeStepViolated : { baseVolumeStep : Nat };
    #PriceDigitsOverflow : { maxDigits : Nat };
    #SessionNumberMismatch : Principal;
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
      case (#VolumeStepViolated { baseVolumeStep }) "Volume step error. Step: " # Nat.toText(baseVolumeStep);
      case (#PriceDigitsOverflow { maxDigits }) "Price digits overflow. Max digits: " # Nat.toText(maxDigits);
      case (#SessionNumberMismatch p) "Session number mismatch for asset " # Principal.toText(p);
    };
  };

  public func getByKeyOrDefault<T, K>(list : AssocList.AssocList<T, K>, key : T, equal : (T, T) -> Bool, default : K) : (K) {
    let ?_value = AssocList.find<T, K>(list, key, equal) else return default;
    _value;
  };

  public func getByKeyOrTrap<T, K>(list : AssocList.AssocList<T, K>, key : T, equal : (T, T) -> Bool, message : Text) : (K) {
    let ?_value = AssocList.find<T, K>(list, key, equal) else Prim.trap(message);
    _value;
  };

  public func require<T>(o : ?T) : T = requireMsg(o, "Required value is null");

  public func requireMsg<T>(opt : ?T, message : Text) : T {
    switch (opt) {
      case (?o) o;
      case (null) Prim.trap(message);
    };
  };

  public func sliceIter<T>(iter : Iter.Iter<T>, limit : Nat, skip : Nat) : [T] {
    var i = 0;
    while (i < skip) {
      let ?_ = iter.next() else return [];
      i += 1;
    };
    i := 0;
    (
      object {
        public func next() : ?T {
          if (i == limit) {
            return null;
          };
          i += 1;
          iter.next();
        };
      }
    ) |> Iter.toArray(_);
  };
};
