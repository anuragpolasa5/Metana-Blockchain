// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./token.sol";

/// @title TestToken - Echidna Exercise 4: Testing with Assertions
/// @author Trail of Bits (Echidna Exercise)
/// @notice Sets up the test environment for assertion-based testing with Echidna.
/// @dev EX4-03: Echidna runs in assertion mode (`testMode: assertion` in config).
///      Instead of explicit property functions, the fuzzer detects assert() failures
///      inside Token.transfer(). The assertions check:
///      1. msg.sender balance must not increase after transfer
///      2. `to` balance must not decrease after transfer
contract TestToken is Token {
    /// @notice The address used by Echidna as the default caller
    address echidna_caller = msg.sender;

    /// @notice Initializes the test with 10000 tokens for assertion testing
    /// @dev EX4-03: Provides initial balance so Echidna can exercise the transfer function
    ///      and attempt to trigger assertion violations
    constructor() {
        balances[echidna_caller] = 10000;
    }
}
