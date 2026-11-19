// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MintableToken.sol";

/// @title TestMintableToken - Echidna Exercise 3: Testing with Custom Initialization
/// @author Trail of Bits (Echidna Exercise)
/// @notice Tests that the minting mechanism respects the totalMintable limit.
/// @dev EX3-02: Uses a custom constructor to initialize totalMintable to 10000.
///      Echidna will call mint() with various values to try to break the invariants.
contract TestMintableToken is MintableToken {
    /// @notice The address used by Echidna as the default caller
    address echidna_caller = msg.sender;

    /// @notice Initializes test with totalMintable set to 10000
    /// @dev EX3-02: Custom initialization demonstrates how to configure Echidna tests
    ///      with specific constructor parameters
    constructor() MintableToken(10000) {
        // The owner is msg.sender (set in Ownership constructor)
        // totalMintable is set to 10000
    }

    /// @notice Echidna property: total minted should never exceed totalMintable
    /// @dev EX3-02: Verifies the core minting invariant holds under fuzzing
    /// @return true if totalMinted <= totalMintable, false if violated
    function echidna_test_minting() public view returns (bool) {
        return totalMinted <= totalMintable;
    }

    /// @notice Echidna property: caller balance should not exceed totalMintable
    /// @dev EX3-02: Secondary invariant ensuring no single address accumulates
    ///      more tokens than the system maximum
    /// @return true if caller balance <= totalMintable, false if violated
    function echidna_test_balance() public view returns (bool) {
        return int(balances[echidna_caller]) <= totalMintable;
    }
}
