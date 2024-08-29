/// A module which contain hardcoded tokens map
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import AssocList "mo:base/AssocList";
import Principal "mo:base/Principal";

module {
  public type TokenInfo = {
    symbol : Text;
    decimals : Nat32;
  };

  public func getTokensInfo() : AssocList.AssocList<Principal, TokenInfo> {
    /// initialize tokens info map
    let symbolsArray : [(Principal, TokenInfo)] = [
      (Principal.fromText("5s5uw-viaaa-aaaaa-aaaaa-aaaaa-aaaaa-aa"), { symbol = "TKN_0"; decimals = 6 }),
      (Principal.fromText("to6hx-qyaaa-aaaaa-aaaaa-aaaaa-aaaaa-ab"), { symbol = "TKN_1"; decimals = 2 }),
      (Principal.fromText("ak2su-6iaaa-aaaaa-aaaaa-aaaaa-aaaaa-ac"), { symbol = "TKN_2"; decimals = 4 }),
    ];

    var symbolsList : AssocList.AssocList<Principal, TokenInfo> = null;

    for ((key, value) in symbolsArray.vals()) {
      symbolsList := AssocList.replace(symbolsList, key, Principal.equal, ?value).0;
    };
    /// end initialize tokens info map

    return symbolsList;
  }
}