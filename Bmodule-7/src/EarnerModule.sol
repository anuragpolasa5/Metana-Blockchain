// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ParticipationToken} from "./ParticipationToken.sol";

/// @title EarnerModule
/// @author Anurag
/// @notice The sole minter of ParticipationToken. Users earn voting power through
///         two on-chain actions:
///
///  1. fund()    – Send ETH to the DAO treasury and earn proportional tokens (capped).
///  2. checkIn() – Claim 1 token per epoch (once per user per epoch).
/// @dev Implements DAO-4 (earning via fund() and checkIn() with epoch caps),
///      DAO-8 (AccessControlDefaultAdminRules, CEI pattern, ReentrancyGuard, Pausable, no tx.origin).
///
/// ─── Earning Caps ────────────────────────────────────────────────────────────
///
///   Epoch duration          : 7 days  (EPOCH_DURATION)
///   Check-in per user/epoch : 1 token (fixed)
///   Funding per user/epoch  : 10 tokens max (FUNDING_USER_CAP)
///   Funding global/epoch    : 100 tokens max (FUNDING_GLOBAL_CAP)
///   Funding rate            : 1 token per 0.01 ETH (FUNDING_RATE = 100 tokens per ETH)
///
/// ─── Security ────────────────────────────────────────────────────────────────
///
///   - AccessControlDefaultAdminRules for role management.
///   - Pausable: pausing blocks fund() and checkIn().
///   - ReentrancyGuard on fund() which calls treasury.
///   - No tx.origin usage.
///   - CEI pattern: all state updates happen BEFORE external call.
///   - Per-user and global epoch caps prevent inflation abuse.
///
contract EarnerModule is AccessControlDefaultAdminRules, Pausable, ReentrancyGuard {
    // ─── Roles ────────────────────────────────────────────────────────────────

    /// @notice Pause/unpause earning actions.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Duration of each participation epoch.
    /// @dev DAO-4: Weekly cadence for Sybil-resistant earning cycles.
    uint256 public constant EPOCH_DURATION = 7 days;

    /// @notice Maximum tokens a single user can earn via funding in one epoch.
    /// @dev DAO-4: Per-user cap prevents whale domination.
    uint256 public constant FUNDING_USER_CAP = 10e18; // 10 tokens

    /// @notice Maximum tokens all users can earn via funding in one epoch combined.
    /// @dev DAO-4: Global cap bounds weekly inflation from funders.
    uint256 public constant FUNDING_GLOBAL_CAP = 100e18; // 100 tokens

    /// @notice Tokens minted per wei of ETH funded (1 token per 0.01 ETH → 100 per ETH).
    /// @dev DAO-4: Rate makes check-in and minimum fund contribution comparable.
    uint256 public constant FUNDING_RATE = 100; // tokens per ETH (scaled by 1e18 internally)

    /// @notice Tokens earned for a successful check-in.
    /// @dev DAO-4: Fixed 1 PART per epoch per user — Sybil-resistant identity action.
    uint256 public constant CHECKIN_REWARD = 1e18; // 1 token

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The participation token this module mints into.
    ParticipationToken public immutable token;

    /// @notice Address where funded ETH is forwarded (DAO treasury).
    address payable public immutable treasury;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @dev epoch → user → tokens earned via funding this epoch.
    mapping(uint256 => mapping(address => uint256)) private _fundingEarned;

    /// @dev epoch → total tokens minted via funding across all users.
    mapping(uint256 => uint256) private _fundingGlobalEarned;

    /// @dev epoch → user → whether check-in has been claimed.
    mapping(uint256 => mapping(address => bool)) private _checkInClaimed;

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice The type of earning action performed.
    enum EarnAction {
        FUND,
        CHECKIN
    }

    /// @notice Emitted whenever a user earns participation tokens.
    /// @param user The address that earned tokens.
    /// @param epoch The epoch in which tokens were earned.
    /// @param amount The number of tokens earned.
    /// @param action The type of action (FUND or CHECKIN).
    event PointsEarned(address indexed user, uint256 indexed epoch, uint256 amount, EarnAction action);

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @dev Reverts when fund() is called with msg.value == 0.
    error ZeroContribution();
    /// @dev Reverts when user has already reached their per-epoch funding cap.
    error UserFundingCapReached();
    /// @dev Reverts when the global per-epoch funding cap has been reached.
    error GlobalFundingCapReached();
    /// @dev Reverts when user has already checked in for the current epoch.
    error AlreadyClaimedCheckIn();
    /// @dev Reverts when ETH forwarding to treasury fails.
    error TreasuryTransferFailed();
    /// @dev Reverts when the calculated mintable amount is zero after cap application.
    error ZeroTokensEarned();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @notice Deploys the EarnerModule linked to a token and treasury.
    /// @dev DAO-8: Uses AccessControlDefaultAdminRules with 2-day delay for secure admin transfer.
    /// @param _token Deployed ParticipationToken address (MINTER_ROLE must be granted to this contract).
    /// @param _treasury Payable treasury address that receives funded ETH.
    /// @param initialAdmin Admin address (DEFAULT_ADMIN_ROLE + PAUSER_ROLE at deploy).
    constructor(address _token, address payable _treasury, address initialAdmin)
        AccessControlDefaultAdminRules(2 days, initialAdmin)
    {
        token = ParticipationToken(_token);
        treasury = _treasury;
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    // ─── Public Views ─────────────────────────────────────────────────────────

    /// @notice Returns the current epoch index (block.timestamp / EPOCH_DURATION).
    /// @dev DAO-4: Epochs are 7-day periods used to bound earning caps.
    /// @return The current epoch number.
    function currentEpoch() public view returns (uint256) {
        return block.timestamp / EPOCH_DURATION;
    }

    /// @notice Whether `user` has already claimed their check-in for `epoch`.
    /// @dev DAO-5: View function for front-end display and test verification.
    /// @param user The address to check.
    /// @param epoch The epoch to query.
    /// @return True if the user has already claimed for this epoch.
    function claimedCheckIn(address user, uint256 epoch) public view returns (bool) {
        return _checkInClaimed[epoch][user];
    }

    /// @notice Tokens `user` can still earn via funding in the current epoch.
    /// @dev DAO-5: View function exposing remaining per-user cap.
    /// @param user The address to check.
    /// @return The remaining tokens the user can earn via funding this epoch.
    function remainingUserCap(address user) external view returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 earned = _fundingEarned[epoch][user];
        return earned >= FUNDING_USER_CAP ? 0 : FUNDING_USER_CAP - earned;
    }

    /// @notice Tokens that can still be minted globally via funding in the current epoch.
    /// @dev DAO-5: View function exposing remaining global cap.
    /// @return The remaining tokens available for all users via funding this epoch.
    function remainingGlobalCap() external view returns (uint256) {
        uint256 epoch = currentEpoch();
        uint256 earned = _fundingGlobalEarned[epoch];
        return earned >= FUNDING_GLOBAL_CAP ? 0 : FUNDING_GLOBAL_CAP - earned;
    }

    // ─── Earning Actions ─────────────────────────────────────────────────────

    /// @notice Fund the treasury with ETH and earn participation tokens.
    /// @dev DAO-4: Rate: FUNDING_RATE tokens per ETH. Capped per user and globally per epoch.
    ///      DAO-8: CEI pattern — state updated BEFORE forwarding ETH to treasury.
    ///      DAO-8: ReentrancyGuard protects against re-entrancy via malicious treasury.
    ///      DAO-8: Pausable — pausing blocks this function.
    ///      Refunds proportional excess ETH when the amount exceeds remaining cap room.
    function fund() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert ZeroContribution();

        uint256 epoch = currentEpoch();
        uint256 rawTokens = (msg.value * FUNDING_RATE); // tokens in token-decimals already scaled

        // DAO-4: Check per-user epoch cap
        uint256 userEarned = _fundingEarned[epoch][msg.sender];
        if (userEarned >= FUNDING_USER_CAP) revert UserFundingCapReached();

        // DAO-4: Check global epoch cap
        uint256 globalEarned = _fundingGlobalEarned[epoch];
        if (globalEarned >= FUNDING_GLOBAL_CAP) revert GlobalFundingCapReached();

        // DAO-4: Apply caps — mint the minimum of raw, user room, and global room
        uint256 mintable = rawTokens;
        uint256 userRoom = FUNDING_USER_CAP - userEarned;
        uint256 globalRoom = FUNDING_GLOBAL_CAP - globalEarned;
        if (mintable > userRoom) mintable = userRoom;
        if (mintable > globalRoom) mintable = globalRoom;
        if (mintable == 0) revert ZeroTokensEarned();

        // Calculate how much ETH corresponds to the capped mintable amount
        // and refund the excess to the sender
        uint256 ethUsed = mintable / FUNDING_RATE;
        uint256 refund = msg.value - ethUsed;

        // DAO-8: Effects – update state before external interaction (CEI pattern)
        _fundingEarned[epoch][msg.sender] = userEarned + mintable;
        _fundingGlobalEarned[epoch] = globalEarned + mintable;

        // DAO-8: Interaction – forward only the used ETH to treasury
        (bool ok,) = treasury.call{value: ethUsed}("");
        if (!ok) revert TreasuryTransferFailed();

        // Refund proportional excess ETH to sender if capped
        if (refund > 0) {
            (bool refundOk,) = payable(msg.sender).call{value: refund}("");
            if (!refundOk) revert TreasuryTransferFailed();
        }

        // DAO-1: Mint participation tokens
        token.mint(msg.sender, mintable);

        emit PointsEarned(msg.sender, epoch, mintable, EarnAction.FUND);
    }

    /// @notice Claim 1 PART token for the current epoch (once per user per epoch).
    /// @dev DAO-4: Fixed reward of 1 PART per epoch — Sybil-resistant identity action.
    ///      DAO-8: Pausable — pausing blocks this function.
    function checkIn() external whenNotPaused {
        uint256 epoch = currentEpoch();
        if (_checkInClaimed[epoch][msg.sender]) revert AlreadyClaimedCheckIn();

        // Effects
        _checkInClaimed[epoch][msg.sender] = true;

        // DAO-1: Mint participation token
        token.mint(msg.sender, CHECKIN_REWARD);

        emit PointsEarned(msg.sender, epoch, CHECKIN_REWARD, EarnAction.CHECKIN);
    }

    // ─── Pause ────────────────────────────────────────────────────────────────

    /// @notice Pause all earning actions. Only callable by PAUSER_ROLE.
    /// @dev DAO-8: Emergency brake for discovered vulnerabilities or oracle attacks.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause earning actions. Only callable by PAUSER_ROLE.
    /// @dev DAO-8: Restores normal operation after emergency is resolved.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
