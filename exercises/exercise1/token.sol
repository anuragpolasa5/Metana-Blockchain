// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownership - Base contract for owner-based access control
/// @author Trail of Bits (Echidna Exercise)
/// @notice Provides basic ownership functionality with a single owner
/// @dev EX1-01: Uses constructor pattern (fixed from vulnerable named-function pattern)
contract Ownership {
    address owner = msg.sender;

    /// @notice Initializes the contract setting the deployer as owner
    /// @dev EX1-01: Proper constructor prevents ownership takeover vulnerability.
    ///      The original buggy version used a public function `Owner()` that anyone could call.
    constructor() {
        owner = msg.sender;
    }

    /// @notice Restricts function access to the contract owner
    /// @dev Reverts with no message if caller is not the owner
    modifier isOwner() {
        require(owner == msg.sender);
        _;
    }
}

/// @title Pausable - Adds pause/resume capability to the contract
/// @notice Allows the owner to pause and resume contract functionality
/// @dev Inherits from Ownership for access control
contract Pausable is Ownership {
    bool is_paused;

    /// @notice Restricts function execution when contract is paused
    /// @dev Reverts if `is_paused` is true
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

/// @title Token - Simple token with transfer functionality
/// @notice Implements a basic token with pausable transfers
/// @dev EX1-02: The transfer function includes a balance check to prevent underflow
contract Token is Pausable {
    mapping(address => uint) public balances;

    /// @notice Transfers tokens from the caller to a recipient
    /// @dev EX1-02: Added `require(balances[msg.sender] >= value)` to fix the underflow bug.
    ///      Without this check, a user could transfer more tokens than they own,
    ///      causing their balance to underflow and gain unlimited tokens.
    /// @param to The recipient address
    /// @param value The amount of tokens to transfer
    function transfer(address to, uint value) public ifNotPaused {
        // EX1-02: Fix - prevent transfer of more tokens than sender owns
        require(balances[msg.sender] >= value);
        balances[msg.sender] -= value;
        balances[to] += value;
    }
}
