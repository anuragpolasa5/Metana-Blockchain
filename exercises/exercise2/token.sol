// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownership - Base contract for owner-based access control
/// @author Trail of Bits (Echidna Exercise)
/// @notice Provides basic ownership functionality with a single owner
/// @dev EX2-01: Uses proper constructor keyword to prevent ownership takeover.
///      The original bug: a public function named `Owner()` allowed anyone to claim ownership.
contract Ownership {
    address owner = msg.sender;

    /// @notice Initializes the contract setting the deployer as owner
    /// @dev EX2-01: Fix applied - using `constructor` instead of named function `Owner()`.
    ///      This ensures ownership can only be set at deployment time.
    constructor() {
        owner = msg.sender;
    }

    /// @notice Restricts function access to the contract owner
    /// @dev Reverts if caller is not the owner
    modifier isOwner() {
        require(owner == msg.sender);
        _;
    }
}

/// @title Pausable - Adds pause/resume capability to the contract
/// @notice Allows the owner to pause and resume contract functionality
/// @dev EX2-02: Once ownership is removed (owner = address(0)), resume() becomes uncallable
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
    /// @dev EX2-02: This function is protected by isOwner modifier.
    ///      When owner is set to address(0), no one can call this function,
    ///      making the pause permanent.
    function resume() public isOwner {
        is_paused = false;
    }
}

/// @title Token - Simple token with transfer functionality
/// @notice Implements a basic token with pausable transfers and balance validation
/// @dev Inherits Pausable for pause mechanism and Ownership for access control
contract Token is Pausable {
    mapping(address => uint) public balances;

    /// @notice Transfers tokens from the caller to a recipient
    /// @dev Protected by ifNotPaused modifier; includes balance validation
    /// @param to The recipient address
    /// @param value The amount of tokens to transfer
    function transfer(address to, uint value) public ifNotPaused {
        require(balances[msg.sender] >= value);
        balances[msg.sender] -= value;
        balances[to] += value;
    }
}
