/// A module which contain implementation of history class and public types
///
/// Copyright: 2023-2024 MR Research AG
/// Main author: Dmitriy Panchenko
/// Contributors: Timo Hanke

import Time "mo:core/Time";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import Float "mo:core/Float";
import Int "mo:core/Int";
import MarketMakerModule "../market-maker-bot-backend/market_maker";

module HistoryModule {
  public type HistoryItemTypeV4 = {
    timestamp : Time.Time;
    pair : ?MarketMakerModule.MarketPairShared;
    bidOrder : ?MarketMakerModule.OrderInfo;
    rate : ?Float;
    message : Text;
  };
  public type HistoryItemTypeV3 = {
    timestamp : Time.Time;
    pair : ?{
      base : MarketMakerModule.TokenDescription;
      base_credits : Nat;
      quote_credits : Nat;
      spread : (value : Float, bias : Float);
    };
    bidOrder : ?MarketMakerModule.OrderInfo;
    rate : ?Float;
    message : Text;
  };

  public func new(
    pair : ?MarketMakerModule.MarketPairShared,
    bidOrder : ?MarketMakerModule.OrderInfo,
    rate : ?Float,
    message : Text,
  ) : HistoryItemTypeV4 = ({
    timestamp = Time.now();
    pair;
    bidOrder;
    rate;
    message;
  });

  public func getText(item : HistoryItemTypeV4) : Text {
    Text.join(
      [
        Int.toText(item.timestamp) # ":  ",
        switch (item.pair) {
          case (?_pair) _pair.base.symbol # " ";
          case (null) "- ";
        },
        switch (item.rate) {
          case (?_rate) "RATE " # Float.toText(_rate) # ", ";
          case (null) "";
        },
        switch (item.bidOrder) {
          case (?_bidOrder) "BID " # Nat.toText(_bidOrder.amount) # " price " # Float.toText(_bidOrder.price) # ", ";
          case (null) "";
        },
        "RESULT " # item.message,
      ].vals(),
      "",
    );
  };
};
