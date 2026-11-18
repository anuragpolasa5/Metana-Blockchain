// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CommunityToken
 * @notice ERC-20 reward token minted by RewardsVault donations.
 *         All permissions are enforced via OpenZeppelin AccessControl —
 *         no Ownable is used anywhere.
 *
 * Roles
 * ─────
 * DEFAULT_ADMIN_ROLE  → granted to `admin` in constructor; can grant/revoke all roles
 * MINTER_ROLE         → may call mint(); intended for the RewardsVault contract
 * PAUSER_ROLE         → may call pause() / unpause()
 */
contract CommunityToken is ERC20, ERC20Pausable, AccessControl {
    // ─────────────────────────────────────────────────────────── roles ──────
    /// @notice Role that authorises token minting (CT-3)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role that authorises pausing / unpausing (CT-6)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ──────────────────────────────────────────────────────── constructor ───
    /**
     * @param name_   ERC-20 token name
     * @param symbol_ ERC-20 token symbol
     * @param admin   Address that receives DEFAULT_ADMIN_ROLE and PAUSER_ROLE (CT-2)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    ) ERC20(name_, symbol_) {
        require(admin != address(0), "CommunityToken: zero admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin); // CT-2
        _grantRole(PAUSER_ROLE, admin);         // CT-2
    }

    // ─────────────────────────────────────────────────────────── minting ────
    /**
     * @notice Mint `amount` tokens to `to`. (CT-4)
     * @dev    Caller must hold MINTER_ROLE.
     */
    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
    {
        _mint(to, amount);
    }

    // ─────────────────────────────────────────────────────────── burning ────
    /**
     * @notice Burn `amount` from the caller's own balance. (CT-5)
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ──────────────────────────────────────────────────────────── pausing ───
    /// @notice Pause all token transfers. (CT-6)
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause all token transfers. (CT-6)
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────── required override (ERC-20) ─
    /**
     * @dev ERC20Pausable requires _update to be overridden when both
     *      ERC20 and ERC20Pausable are in the inheritance chain.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
