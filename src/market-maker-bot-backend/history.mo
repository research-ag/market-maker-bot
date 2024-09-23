/// A module which contain implementation of history class and public types
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Time "mo:base/Time";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Int "mo:base/Int";
import MarketMakerModule "./market_maker";

module HistoryModule {
  public type HistoryItemType = {
    timestamp : Time.Time;
    pair : MarketMakerModule.MarketPairShared;
    bidOrder : ?MarketMakerModule.OrderInfo;
    askOrder : ?MarketMakerModule.OrderInfo;
    rate : ?Float;
    message : Text;
  };

  public func new(
    pair : MarketMakerModule.MarketPair,
    bidOrder : ?MarketMakerModule.OrderInfo,
    askOrder : ?MarketMakerModule.OrderInfo,
    rate : ?Float,
    message : Text,
  ) : HistoryItemType = ({
    timestamp = Time.now();
    pair = MarketMakerModule.sharePair(pair);
    bidOrder;
    askOrder;
    rate;
    message;
  });

  public func getText(item : HistoryItemType) : Text {
    Text.join(
      "",
      [
        Int.toText(item.timestamp) # ":  ",
        item.pair.base_symbol # ":" # item.pair.quote_symbol # " ",
        switch (item.rate) {
          case (?_rate) "RATE " # Float.toText(_rate) # ", ";
          case (null) "";
        },
        switch (item.bidOrder) {
          case (?_bidOrder) "BID " # Nat.toText(_bidOrder.amount) # " price " # Float.toText(_bidOrder.price) # ", ";
          case (null) "";
        },
        switch (item.askOrder) {
          case (?_askOrder) "ASK " # Nat.toText(_askOrder.amount) # " price " # Float.toText(_askOrder.price) # ", ";
          case (null) "";
        },
        "RESULT " # item.message,
      ].vals(),
    );
  };
};
