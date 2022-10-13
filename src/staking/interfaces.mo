module {
  public type TxReceipt = {
    #Ok : Nat;
    #Err : {
      #InsufficientAllowance;
      #InsufficientBalance;
      #ErrorOperationStyle;
      #Unauthorized;
      #LedgerTrap;
      #ErrorTo;
      #Other : Text;
      #BlockUsed;
      #AmountTooSmall;
    };
  };
  public type Token = actor {
    transfer : shared (Principal, Nat) -> async ();
    transferFrom : shared (Principal, Principal, Nat) -> async (TxReceipt);
  };
};
