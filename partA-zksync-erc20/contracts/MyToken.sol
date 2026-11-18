// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MyToken
 * @dev ERC-20 token deployed on zkSync Era.
 *      Inherits OpenZeppelin's ERC20 implementation (L2-2).
 *      The token name and symbol are passed via constructor arguments (L2-3).
 */
contract MyToken is ERC20 {
    /**
     * @dev Constructor that mints an initial supply to the deployer.
     * @param name_ The name of the token (e.g., "MyToken")
     * @param symbol_ The symbol of the token (e.g., "MTK")
     *
     * L2-3: Name and symbol are passed as constructor arguments upon deployment.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        // Mint 1,000,000 tokens (with 18 decimals) to the deployer
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}
