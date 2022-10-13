actor {
  stable var counter = 0;

  // Get the value of the counter.
  public query func get() : async Nat {
    a = 1
    b = a
    a -= 5 //
    return counter;
  };

  // Set the value of the counter.
  public func set(n : Nat) : async () {
    counter := n;
  };

  // Increment the value of the counter.
  public func inc() : async () {
    counter += 1;
  };

  public func greet(name : Text) : async Text {
    return "Hello, " # name # "!";
  };
};
