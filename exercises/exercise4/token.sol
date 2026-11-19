// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownership - Base contract for owner-based access control
/// @author Trail of Bits (Echidna Exercise)
/// @notice Provides basic ownership functionality with a single owner
contract Ownership {
    address owner = msg.sender;

    /// @notice Initializes the contract setting the deployer as owner
    constructor() {
        owner = msg.sender;
    }

    /// @notice Restricts function access to the contract owner
    modifier isOwner() {
        require(owner == msg.sender);
        _;
    }
}

/// @title Pausable - Adds pause/resume capability to the contract
/// @notice Allows the owner to pause and resume contract functionality
contract Pausable is Ownership {
    bool is_paused;

    /// @notice Restricts function execution when contract is paused
    modifier ifNotPaused() {
        require(!is_paused);
        _;
    }

    /// @notice Pauses the contract, preventing transfers
    /// @dev Only callable by the owner
    function paused() public isOwner {
        is_paused = true;
    }

    /// @notice Resumes the contract, re-enabling transfers
    /// @dev Only callable by the owner
    function resume() public isOwner {
        is_paused = false;
    }
}

/// @title Token - Exercise 4: Testing with Assertions
/// @author Trail of Bits (Echidna Exercise)
/// @notice The transfer function includes assertions to verify balance invariants.
/// @dev EX4-01: Uses assert() statements as post-conditions to verify transfer correctness.
///      Echidna runs in assertion mode to detect assert() violations.
contract Token is Pausable {
    mapping(address => uint) public balances;

    /// @notice Transfers tokens with assertion-based invariant checks
    /// @dev EX4-01: Asserts that sender balance can only decrease and receiver balance
    ///      can only increase after a transfer. These are post-condition invariants.
    ///      EX4-02: The require() fix prevents underflow that would violate the assertions.
    ///      Without the require, `balances[msg.sender] -= value` could wrap around,
    ///      making the sender's balance larger than before (violating the first assert).
    /// @param to The recipient address
    /// @param value The amount of tokens to transfer
    function transfer(address to, uint value) public ifNotPaused {
        // EX4-01: Capture initial balances for post-condition checks
        uint senderBalance = balances[msg.sender];
        uint receiverBalance = balances[to];

        // EX4-02: Fix - prevent underflow by requiring sufficient balance
        require(balances[msg.sender] >= value);

        balances[msg.sender] -= value;
        balances[to] += value;

        // EX4-01: Post-condition assertions verify transfer correctness
        assert(balances[msg.sender] <= senderBalance);  // sender balance must decrease or stay same
        assert(balances[to] >= receiverBalance);         // receiver balance must increase or stay same
    }
}
