// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./token.sol";

/// @title MintableToken - Extension of Token with minting capability
/// @author Trail of Bits (Echidna Exercise)
/// @notice Only the owner can mint new tokens, up to a maximum total mintable amount.
/// @dev EX3-01: Extends Token with a controlled minting mechanism that enforces supply limits.
contract MintableToken is Token {
    /// @notice Total amount of tokens minted so far
    int public totalMinted;

    /// @notice Maximum total tokens that can ever be minted
    int public totalMintable;

    /// @notice Initializes the mintable token with a maximum supply cap
    /// @dev EX3-01: The totalMintable parameter sets the upper bound for minting
    /// @param _totalMintable The maximum number of tokens that can be minted
    constructor(int _totalMintable) {
        totalMintable = _totalMintable;
    }

    /// @notice Mints new tokens to the owner's balance
    /// @dev EX3-01: Enforces that cumulative minting stays below totalMintable.
    ///      Uses int type for totalMinted/totalMintable comparison.
    ///      Note: casting uint to int is safe under Solidity 0.8+ overflow protection.
    /// @param value The amount of tokens to mint
    function mint(uint value) public isOwner {
        // EX3-01: Ensure minting does not exceed the totalMintable limit
        require(int(value) + totalMinted < totalMintable);
        totalMinted += int(value);
        balances[msg.sender] += value;
    }
}
