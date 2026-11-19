// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./token.sol";

/// @title TestToken - Echidna Exercise 2: Testing Access Control
/// @author Trail of Bits (Echidna Exercise)
/// @notice Tests that once paused with ownership removed, the contract cannot be unpaused.
/// @dev EX2-03: The constructor pauses the contract and sets owner to address(0).
///      The property verifies that `is_paused` remains true regardless of what Echidna tries.
contract TestToken is Token {
    /// @notice The address used by Echidna as the default caller
    address echidna_caller = msg.sender;

    /// @notice Initializes test: pauses contract and removes ownership
    /// @dev EX2-03: Simulates a scenario where the contract is permanently paused.
    ///      Setting owner to address(0) means no address can satisfy the isOwner modifier.
    constructor() {
        // EX2-03: Pause the contract at deployment
        paused();
        // EX2-03: Remove ownership so no one can call resume()
        owner = address(0x0);
    }

    /// @notice Echidna property: the contract should never be unpaused
    /// @dev EX2-03: This property PASSES after the constructor fix (using `constructor` keyword).
    ///      Before the fix, Echidna could call the public `Owner()` function to reclaim
    ///      ownership and then call `resume()` to unpause the contract.
    /// @return true if the contract remains paused, false if somehow unpaused
    function echidna_no_transfer() public view returns (bool) {
        return is_paused == true;
    }
}
