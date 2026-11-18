// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/**
 * @title LearnToken
 * @notice Capped ERC20 token with role-based minting.
 *
 * FE-1  – ERC20 with custom name, symbol, decimals, and MAX_SUPPLY;
 *          all set via constructor parameters.
 * FE-2  – Supply cap enforced by overriding _update() (delegates to ERC20Capped._update).
 * FE-3  – Only accounts with MINTER_ROLE may call mint();
 *          role management via AccessControlDefaultAdminRules (1-day admin-transfer delay).
 *
 * Inheritance chain:
 *   LearnToken → ERC20Capped → ERC20
 *              → AccessControlDefaultAdminRules → AccessControl
 */
contract LearnToken is ERC20Capped, AccessControlDefaultAdminRules {
    // ────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────

    /// @notice Role identifier for accounts that may mint new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ────────────────────────────────────────────────────────────────────────
    // State
    // ────────────────────────────────────────────────────────────────────────

    /// @notice Custom decimals for this token (overrides ERC20 default of 18).
    uint8 private immutable _decimals;

    // ────────────────────────────────────────────────────────────────────────
    // Constructor
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @param _name            Token name (e.g. "LearnToken").
     * @param _symbol          Token symbol (e.g. "LRN").
     * @param _tokenDecimals   Number of decimals (e.g. 18).
     * @param _maxSupplyUnits  Maximum number of tokens in WHOLE units (scaled ×10**decimals internally).
     * @param admin            Address that receives DEFAULT_ADMIN_ROLE on deployment.
     *
     * @dev  AccessControlDefaultAdminRules is initialised with a 1-day admin-transfer delay.
     *       ERC20Capped stores the cap as `_maxSupplyUnits * 10**decimals` wei.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _tokenDecimals,
        uint256 _maxSupplyUnits,
        address admin
    )
        ERC20(_name, _symbol)
        ERC20Capped(_maxSupplyUnits * 10 ** _tokenDecimals)
        AccessControlDefaultAdminRules(1 days, admin)
    {
        _decimals = _tokenDecimals;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Minting
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @notice Mint `amount` tokens (in wei) to `to`.
     * @dev    Restricted to MINTER_ROLE. The supply cap is enforced automatically
     *         through the _update() override below.
     *
     * FE-3: Only accounts with MINTER_ROLE can mint.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Internal overrides
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @dev Returns the number of decimals used for token amounts.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev ERC20Capped overrides _update() from ERC20; since our contract directly
     *      inherits ERC20Capped (which already extends ERC20), we only need to specify
     *      ERC20Capped in the override list.
     *
     * FE-2: Supply cap is enforced here via ERC20Capped._update().
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Capped)
    {
        super._update(from, to, value);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Views
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the maximum token supply in wei (same as cap()).
     */
    function maxSupply() external view returns (uint256) {
        return cap();
    }
}
