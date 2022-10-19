import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Error "mo:base/Error";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Debug "mo:base/Debug";

import Account "./Account";
import Interfaces "./Interfaces";
import LedgerInterface "./LedgerInterface";

actor Staking {
  var acceptedToken = "sgymv-uiaaa-aaaaa-aaaia-cai";
  var rewardToken = "sgymv-uiaaa-aaaaa-aaaia-cai";
  var ledger : LedgerInterface.ILedger = actor ("qoctq-giaaa-aaaaa-aaaea-cai");
  var rewardDistributor = "";
  stable var APR = 50; // 50 / ONE_HUNDRED = 50 / 10000 = 0.5%

  stable let ONE_YEAR_IN_SECOND = 86400 * 365;
  stable let ONE_HUNDRED = 10000;

  private var balances = HashMap.HashMap<Principal, Nat>(1, Principal.equal, Principal.hash);
  private var updateTimes = HashMap.HashMap<Principal, Nat64>(1, Principal.equal, Principal.hash);

  private func isAnonymous(p : Principal) : Bool {
    Blob.equal(Principal.toBlob(p), Blob.fromArray([0x04]));
  };

  private func _balanceOf(who : Principal) : Nat {
    switch (balances.get(who)) {
      case (?balance) { return balance };
      case (_) { return 0 };
    };
  };

  private func _timeOf(who : Principal) : Nat64 {
    switch (updateTimes.get(who)) {
      case (?time) { return time };
      case (_) { return 0 };
    };
  };

  public func balanceOf(who : Principal) : async Nat {
    return _balanceOf(who);
  };

  // reentrancy??
  public shared (msg) func stake(amount : Nat) : async () {
    // check anonymous
    if (isAnonymous(msg.caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    ignore await _claim(msg.caller);

    // increase stakeAmount
    let oldBalance = _balanceOf(msg.caller);
    balances.put(msg.caller, oldBalance + amount);

    // transfer token to this wallet
    let acceptedTokenInstance : Interfaces.Token = actor (acceptedToken);
    ignore await acceptedTokenInstance.transferFrom(msg.caller, Principal.fromActor(Staking), amount);
  };

  public shared (msg) func stakeWithICP(amount : Nat) : async () {
    if (acceptedToken != "") {
      throw Error.reject("Not allow to stake ICP");
    };

    // check anonymous
    if (isAnonymous(msg.caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    let test : ?LedgerInterface.SubAccount = ?Account.accountIdentifier(Principal.fromActor(Staking), Account.principalToSubaccount(msg.caller));
    Debug.print("===================");
    Debug.print("======== " # debug_show test);
    ignore await _claim(msg.caller);

    // get ICP and send to this canister
    let balanceBefore = await ledger.account_balance({ account = myAccountId() });

    let now = Time.now();
    let res = await ledger.transfer({
      memo = 0;
      from_subaccount = test;
      to = Account.accountIdentifier(me(), Account.defaultSubaccount());
      amount = { e8s = Nat64.fromNat(amount) };
      fee = { e8s = 0 };
      created_at_time = ?{ timestamp_nanos = Nat64.fromNat(Int.abs(now)) };
    });
    switch (res) {
      case (#Ok(blockIndex)) {
        Debug.print("Paid reward to " # debug_show me() # " in block " # debug_show blockIndex);
      };
      case (#Err(#InsufficientFunds { balance })) {
        throw Error.reject("Top me up! The balance is only " # debug_show balance # " e8s");
      };
      case (#Err(other)) {
        throw Error.reject("Unexpected error: " # debug_show other);
      };
    };

    let balanceAfter : LedgerInterface.Tokens = await ledger.account_balance({
      account = myAccountId();
    });

    if (Nat64.toNat(balanceAfter.e8s) - Nat64.toNat(balanceBefore.e8s) != amount) return;

    // increase stakeAmount
    let oldBalance = _balanceOf(msg.caller);
    balances.put(msg.caller, oldBalance + amount);
  };

  public func getICPBalance() : async LedgerInterface.Tokens {
    await ledger.account_balance({ account = myAccountId() });
  };

  public shared (msg) func testTransfer(amount : Nat) : async () {
    let test : ?LedgerInterface.SubAccount = ?Account.principalToSubaccount(msg.caller);
    let balance = await ledger.account_balance({
      account = Account.accountIdentifier(Principal.fromActor(Staking), Account.principalToSubaccount(msg.caller));
    });

    Debug.print("===================" # debug_show balance);
    Debug.print("======== " # debug_show test);

    let now = Time.now();
    let res = await ledger.transfer({
      memo = 0;
      from_subaccount = test;
      to = Account.accountIdentifier(me(), Account.defaultSubaccount());
      amount = { e8s = Nat64.fromNat(amount) };
      fee = { e8s = 10000 };
      created_at_time = ?{ timestamp_nanos = Nat64.fromNat(Int.abs(now)) };
    });
    switch (res) {
      case (#Ok(blockIndex)) {
        Debug.print("Paid reward to " # debug_show me() # " in block " # debug_show blockIndex);
      };
      case (#Err(#InsufficientFunds { balance })) {
        throw Error.reject("Top me up! The balance is only " # debug_show balance # " e8s");
      };
      case (#Err(other)) {
        throw Error.reject("Unexpected error: " # debug_show other);
      };
    };
  };

  // Returns canister's default account identifier as a blob.
  public query func canisterAccount() : async Account.AccountIdentifier {
    myAccountId();
  };

  public shared (msg) func withdraw(amount : Nat) : async () {
    // check anonymous
    if (isAnonymous(msg.caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    // claim reward
    ignore await _claim(msg.caller);

    // check balance
    let oldBalance = _balanceOf(msg.caller);
    if (oldBalance < amount) {
      throw Error.reject("not enought balance to withdraw");
    };

    // decrease stakeAmount
    balances.put(msg.caller, oldBalance - amount);

    // transfer withdrawAmount
    let rewardTokenInstance : Interfaces.Token = actor (rewardToken);
    ignore await rewardTokenInstance.transferFrom(msg.caller, Principal.fromActor(Staking), amount);

  };

  public shared (msg) func claim(amount : Nat) : async () {
    // check anonymous
    if (isAnonymous(msg.caller)) {
      throw Error.reject("anonymous user is not allowed to transfer funds");
    };

    // claim reward
    ignore await _claim(msg.caller);
  };

  public query func pendingReward(user : Principal) : async Nat {
    let userBalance = _balanceOf(user);
    if (userBalance == 0) return 0;

    let now = Nat64.fromNat(Int.abs(Time.now()));
    let lastClaimTime = _timeOf(user);
    if (lastClaimTime == 0) throw Error.reject("time cannot be 0");
    let stakeTime = Nat64.toNat(now - lastClaimTime);
    return (_balanceOf(user) * APR * stakeTime) / (ONE_HUNDRED * ONE_YEAR_IN_SECOND);
  };

  private func _claim(user : Principal) : async Nat {
    // cal reward for user
    let reward : Nat = await pendingReward(user);

    // transfer reward
    let rewardTokenInstance : Interfaces.Token = actor (rewardToken);
    ignore await rewardTokenInstance.transferFrom(user, Principal.fromActor(Staking), reward);

    // update time that balance of user changed
    _updateTimes(user);

    return reward;
  };

  private func _updateTimes(user : Principal) : () {
    let now = Nat64.fromNat(Int.abs(Time.now()));
    updateTimes.put(user, now);
  };

  // Returns the default account identifier of this canister.
  private func myAccountId() : Account.AccountIdentifier {
    Account.accountIdentifier(Principal.fromActor(Staking), Account.defaultSubaccount());
  };

  // Returns the default account identifier of this canister.
  private func me() : Principal {
    Principal.fromActor(Staking);
  };

  public shared (msg) func getDepositAddress() : async Account.AccountIdentifier {
    Account.accountIdentifier(Principal.fromActor(Staking), Account.principalToSubaccount(msg.caller));
  };

  public shared (msg) func getDepositAddressInText() : async Principal {
    let account : Blob = Account.accountIdentifier(Principal.fromActor(Staking), Account.principalToSubaccount(msg.caller));
    return Principal.fromBlob(account);
  };
};
