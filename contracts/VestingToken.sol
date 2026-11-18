// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title VestingToken – standard ERC-20 token whose minting is gated to VestingVault.
/// @notice 100 000 000 tokens are minted to the admin at deployment.
///         Only addresses holding MINTER_ROLE (i.e. the vault) may mint further.
contract VestingToken is ERC20, ERC20Burnable, AccessControl {
    /// @notice Role that allows an address to mint new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─── Custom errors ────────────────────────────────────────────────────────
    error ZeroAdminAddress();

    constructor(
        string memory name,
        string memory symbol,
        address admin
    ) ERC20(name, symbol) {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _mint(admin, 100_000_000 * 10 ** decimals()); // 100 million tokens
    }

    /// @notice Mint `amount` tokens to `to`. Callable only by MINTER_ROLE (the vault).
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}