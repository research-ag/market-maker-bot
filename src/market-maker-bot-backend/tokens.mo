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
      (Principal.fromText("cngnf-vqaaa-aaaar-qag4q-cai"), { symbol = "USDT"; decimals = 6 }),
      (Principal.fromText("xevnm-gaaaa-aaaar-qafnq-cai"), { symbol = "USDC"; decimals = 6 }),
      (Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai"), { symbol = "ICP"; decimals = 8 }),
      (Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai"), { symbol = "BTC"; decimals = 8 }),
      (Principal.fromText("ss2fx-dyaaa-aaaar-qacoq-cai"), { symbol = "ETH"; decimals = 18 }),
    ];

    var symbolsList : AssocList.AssocList<Principal, TokenInfo> = null;

    for ((key, value) in symbolsArray.vals()) {
      symbolsList := AssocList.replace(symbolsList, key, Principal.equal, ?value).0;
    };
    /// end initialize tokens info map

    return symbolsList;
  }
}