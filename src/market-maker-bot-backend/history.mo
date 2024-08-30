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
    timestamp: Time.Time;
    pair: MarketMakerModule.MarketPair;
    bidOrder : ?MarketMakerModule.OrderInfo;
    askOrder : ?MarketMakerModule.OrderInfo;
    rate : ?Float;
    message : Text;
  };

  public class HistoryItem(pair: MarketMakerModule.MarketPair,
    bidOrder : ?MarketMakerModule.OrderInfo,
    askOrder : ?MarketMakerModule.OrderInfo,
    rate : ?Float,
    message : Text) {
    let timeStamp : Time.Time = Time.now();

    public func getText() : (Text) {
      Text.join("", [
        Int.toText(timeStamp) # ":  ",
        pair.base_symbol # ":" # pair.quote_symbol # " ",
        switch (rate) {
          case (?_rate) "RATE " # Float.toText(_rate) # ", ";
          case (null) "";
        },
        switch (bidOrder) {
          case (?_bidOrder) "BID " # Nat.toText(_bidOrder.amount) # " price " # Float.toText(_bidOrder.price) # ", ";
          case (null) "";
        },
        switch (askOrder) {
          case (?_askOrder) "ASK " # Nat.toText(_askOrder.amount) # " price " # Float.toText(_askOrder.price) # ", ";
          case (null) "";
        },
        "RESULT " # message
      ].vals());
    };

    public func getItem() : (HistoryItemType) {
      {
        timestamp = timeStamp;
        pair = pair;
        bidOrder = bidOrder;
        askOrder = askOrder;
        rate = rate;
        message = message;
      };
    };
  }
}
