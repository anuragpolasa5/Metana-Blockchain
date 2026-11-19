// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ownership - Base contract for owner-based access control
/// @author Trail of Bits (Echidna Exercise)
/// @notice Provides basic ownership functionality with a single owner
/// @dev Uses constructor for secure ownership initialization
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

/// @title Token - Simple token with transfer functionality
/// @notice Implements a basic token with pausable transfers and balance validation
contract Token is Pausable {
    mapping(address => uint) public balances;

    /// @notice Transfers tokens from the caller to a recipient
    /// @param to The recipient address
    /// @param value The amount of tokens to transfer
    function transfer(address to, uint value) public ifNotPaused {
        require(balances[msg.sender] >= value);
        balances[msg.sender] -= value;
        balances[to] += value;
    }
}
