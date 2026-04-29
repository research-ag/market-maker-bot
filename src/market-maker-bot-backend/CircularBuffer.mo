import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";
import VarArray "mo:core/VarArray";

module CircularBuffer {

  public type CircularBuffer<T> = {
    array : [var ?T];
    capacity : Nat;
    var ptr : Nat;
    var pushes : Nat;
  };

  public func new<T>(capacity : Nat) : CircularBuffer<T> {
    assert capacity != 0;
    { array = VarArray.repeat(null, capacity); capacity; var ptr = 0; var pushes = 0 };
  };

  public func size<T>(self : CircularBuffer<T>) : Nat = self.pushes;

  public func capacity<T>(self : CircularBuffer<T>) : Nat = self.capacity;

  /// Insert value into the buffer
  public func add<T>(self : CircularBuffer<T>, item : T) {
    self.array[self.ptr] := ?item;
    self.pushes += 1;
    self.ptr += 1;
    if (self.ptr == self.capacity) self.ptr := 0;
  };

  /// Return interval `[start, end)` of indices of elements available.
  public func available<T>(self : CircularBuffer<T>) : (Nat, Nat) {
    (if (self.pushes <= self.capacity) 0 else self.pushes - self.capacity, self.pushes);
  };

  /// Returns single element added with number `index` or null if element is not available or index out of bounds.
  public func get<T>(self : CircularBuffer<T>, index : Nat) : ?T {
    let (l, r) = available(self);
    if (l <= index and index < r) { self.array[index % self.capacity] } else {
      null;
    };
  };

  public func at<T>(self : CircularBuffer<T>, index : Nat) : T {
    switch (get(self, index)) {
      case (?item) item;
      case null Runtime.trap("Index out of bounds");
    };
  };

  public func availableValues<T>(self : CircularBuffer<T>) : Iter.Iter<T> {
    let (l, r) = available(self);
    Nat.range(l, r).map(func(i : Nat) : T = at(self, i));
  };

  public func reverseAvailableValues<T>(self : CircularBuffer<T>) : Iter.Iter<T> {
    let (l, r) = available(self);
    if (r == 0) return Iter.empty();
    Nat.rangeByInclusive(r - 1, l, -1).map(func(i : Nat) : T = at(self, i));
  };

  public func values<T>(self : CircularBuffer<T>) : Iter.Iter<?T> {
    Nat.range(0, self.pushes).map(func(i : Nat) : ?T = get(self, i));
  };

  public func reverseValues<T>(self : CircularBuffer<T>) : Iter.Iter<?T> {
    if (self.pushes == 0) return Iter.empty();
    Nat.rangeByInclusive(self.pushes - 1, 0, -1).map(func(i : Nat) : ?T = get(self, i));
  };

};
