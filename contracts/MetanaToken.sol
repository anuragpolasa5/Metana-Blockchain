// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title MetanaToken (MTN)
/// @author Anurag
/// @notice Simple ERC20 token with mint functionality. Name: METANA, Symbol: MTN.
/// @dev Deployed as the underlying token for the entire DeFi system.
///      Used as the staking token in MTNStaking and the base asset for wMTN wrapping.
contract MetanaToken is ERC20, Ownable {
    /// @notice Deploys the MetanaToken with name "METANA" and symbol "MTN".
    /// @dev Sets deployer as the owner who can mint tokens.
    constructor() ERC20("METANA", "MTN") Ownable(msg.sender) {}

    /// @notice Mint new MTN tokens to a specified address.
    /// @dev Only callable by the contract owner. No max supply cap enforced.
    /// @param to The recipient address to receive minted tokens.
    /// @param amount The number of tokens to mint (in wei).
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
