// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DamnValuableToken
/// @author Damn Vulnerable DeFi
/// @notice A simple ERC20 token used in the Unstoppable challenge
/// @dev Mints the maximum possible supply to the deployer at construction
contract DamnValuableToken is ERC20 {
    /// @notice Deploys the token and mints max supply to deployer
    constructor() ERC20("DamnValuableToken", "DVT") {
        _mint(msg.sender, type(uint256).max);
    }
}
