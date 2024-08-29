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
    pair: MarketMakerModule.MarketPair;
    bidOrder : MarketMakerModule.OrderInfo;
    askOrder : MarketMakerModule.OrderInfo;
    message : Text;
  };

  public class HistoryItem(pair : MarketMakerModule.MarketPair, bidOrder : MarketMakerModule.OrderInfo, askOrder : MarketMakerModule.OrderInfo, message : Text) {
    let timeStamp : Time.Time = Time.now();

    public func getText() : (Text) {
      Text.join("", [
        Int.toText(timeStamp), ":  ",
        pair.base_symbol, ":", pair.quote_symbol, " ",
        "BID ", Nat.toText(bidOrder.amount), " price ", Float.toText(bidOrder.price), ", ",
        "ASK ", Nat.toText(askOrder.amount), " price ", Float.toText(askOrder.price), ", ",
        "RESULT ", message
      ].vals());
    };

    public func getItem() : (HistoryItemType) {
      {
        pair = pair;
        bidOrder = bidOrder;
        askOrder = askOrder;
        message = message;
      };
    };
  }
}
