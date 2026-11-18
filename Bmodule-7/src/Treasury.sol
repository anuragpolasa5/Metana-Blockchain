// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Treasury
/// @author Anurag
/// @notice Holds ETH and ERC-20 tokens on behalf of the DAO.
///         All payout paths are restricted to the TimelockController (TIMELOCK_ROLE).
/// @dev Implements DAO-3 (Treasury owned by Timelock, nonReentrant payouts),
///      DAO-7 (concrete proposal actions: releaseETH + setParam),
///      DAO-8 (ReentrancyGuard, CEI, Pausable, AccessControlDefaultAdminRules, no tx.origin).
///
/// ─── Security ────────────────────────────────────────────────────────────────
///   - ReentrancyGuard on releaseETH (CEI + guard = defence-in-depth).
///   - No tx.origin.
///   - Non-zero address and balance checks before every transfer.
///   - Pausable: pause blocks releaseETH and releaseERC20.
///   - setParam purely updates an on-chain config mapping (no value transfer).
///
contract Treasury is AccessControlDefaultAdminRules, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Roles ────────────────────────────────────────────────────────────────

    /// @notice Role granted to the TimelockController. Required to execute payouts or param updates.
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");

    /// @notice Role granted to PAUSER addresses.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Arbitrary governance-controlled parameters (e.g., grant limits, fee rates).
    /// @dev DAO-7: Parameters can be updated via governance proposals (setParam).
    mapping(bytes32 => uint256) public params;

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when ETH is released to a grantee.
    /// @param grantee The recipient of the ETH grant.
    /// @param amount The amount of ETH released in wei.
    event GrantReleased(address indexed grantee, uint256 amount);

    /// @notice Emitted when ERC-20 tokens are released to a grantee.
    /// @param token The ERC-20 token address.
    /// @param grantee The recipient of the token grant.
    /// @param amount The amount of tokens released.
    event ERC20Released(address indexed token, address indexed grantee, uint256 amount);

    /// @notice Emitted when a governance parameter is updated.
    /// @param key The parameter key.
    /// @param value The new parameter value.
    event ParamUpdated(bytes32 indexed key, uint256 value);

    /// @notice Emitted when ETH is received by the treasury.
    /// @param sender The address that sent ETH.
    /// @param amount The amount of ETH received in wei.
    event Received(address indexed sender, uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @dev Reverts when a zero address is provided as grantee or token.
    error ZeroAddress();
    /// @dev Reverts when requested amount exceeds treasury balance.
    error InsufficientBalance(uint256 requested, uint256 available);
    /// @dev Reverts when a zero amount is provided.
    error ZeroAmount();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @notice Deploys the Treasury with admin and timelock roles configured.
    /// @dev DAO-3: Treasury is owned by the Timelock — only governance can release funds.
    ///      DAO-8: AccessControlDefaultAdminRules with 2-day delay for secure admin transfer.
    ///      Zero-address validation prevents accidental misconfiguration at deploy time.
    /// @param initialAdmin Admin/owner (will transfer DEFAULT_ADMIN_ROLE to Timelock post-deploy).
    /// @param timelockAddr TimelockController address — receives TIMELOCK_ROLE immediately.
    constructor(address initialAdmin, address timelockAddr)
        AccessControlDefaultAdminRules(2 days, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (timelockAddr == address(0)) revert ZeroAddress();
        _grantRole(TIMELOCK_ROLE, timelockAddr);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    // ─── ETH Management ──────────────────────────────────────────────────────

    /// @notice Receives ETH sent to the treasury.
    /// @dev Emits a Received event for tracking incoming funds.
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// @notice Release `amount` wei of ETH to `grantee`.
    /// @dev DAO-3: Only callable by TIMELOCK_ROLE (governance-approved proposals only).
    ///      DAO-7: This is a concrete proposal action — proposals can call releaseETH.
    ///      DAO-8: ReentrancyGuard + CEI pattern for defence-in-depth against re-entrancy.
    /// @param grantee The payable address to receive the ETH.
    /// @param amount The amount of ETH in wei to release.
    function releaseETH(address payable grantee, uint256 amount)
        external
        onlyRole(TIMELOCK_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (grantee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (amount > bal) revert InsufficientBalance(amount, bal);

        // DAO-8: Effects before interaction (CEI pattern)
        emit GrantReleased(grantee, amount);

        // Interaction
        (bool ok,) = grantee.call{value: amount}("");
        require(ok, "Treasury: ETH transfer failed");
    }

    // ─── ERC-20 Management ───────────────────────────────────────────────────

    /// @notice Release `amount` of ERC-20 `tokenAddr` to `grantee`.
    /// @dev DAO-3: Only callable by TIMELOCK_ROLE. Uses SafeERC20 for safe transfers.
    ///      DAO-8: ReentrancyGuard + Pausable for additional security.
    /// @param tokenAddr The ERC-20 token contract address.
    /// @param grantee The recipient address.
    /// @param amount The number of tokens to release.
    function releaseERC20(address tokenAddr, address grantee, uint256 amount)
        external
        onlyRole(TIMELOCK_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (grantee == address(0) || tokenAddr == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 bal = IERC20(tokenAddr).balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance(amount, bal);

        emit ERC20Released(tokenAddr, grantee, amount);
        IERC20(tokenAddr).safeTransfer(grantee, amount);
    }

    // ─── Parameter Store ─────────────────────────────────────────────────────

    /// @notice Update an on-chain governance parameter.
    /// @dev DAO-7: Concrete proposal action — governance can update arbitrary params.
    ///      No value transfer — safe from reentrancy by design.
    /// @param key The bytes32 key identifying the parameter.
    /// @param value The new uint256 value to store.
    function setParam(bytes32 key, uint256 value) external onlyRole(TIMELOCK_ROLE) {
        params[key] = value;
        emit ParamUpdated(key, value);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    /// @notice Returns the current ETH balance of the treasury.
    /// @dev DAO-5: View function for front-end and test verification.
    /// @return The ETH balance in wei.
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns the current ERC-20 balance of the treasury for a given token.
    /// @dev DAO-5: View function for front-end and test verification.
    /// @param tokenAddr The ERC-20 token contract address to query.
    /// @return The token balance held by this treasury.
    function erc20Balance(address tokenAddr) external view returns (uint256) {
        return IERC20(tokenAddr).balanceOf(address(this));
    }

    // ─── Pause ────────────────────────────────────────────────────────────────

    /// @notice Pause all payout operations. Only callable by PAUSER_ROLE.
    /// @dev DAO-8: Emergency brake for discovered vulnerabilities.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause payout operations. Only callable by PAUSER_ROLE.
    /// @dev DAO-8: Restores normal operation after emergency is resolved.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
