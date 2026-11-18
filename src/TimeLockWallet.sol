// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title  TimeLockWallet
 * @notice Allows anyone to lock ETH for a beneficiary until a future timestamp.
 *         Supports multiple locks per beneficiary, batch claiming, depositor
 *         reclaim after a grace period, and a small protocol fee accrued on
 *         every payout.
 *
 * Security properties:
 *  - nonReentrant on every ETH-moving function (claim, batchClaim, reclaim,
 *    withdrawFees).
 *  - Strict checks-effects-interactions throughout.
 *  - No tx.origin usage.
 *  - Direct ETH transfers (receive / fallback) always revert.
 *  - Pause controls block creation, claims, reclaims, batch claims, and fee
 *    withdrawals while paused.
 */
contract TimeLockWallet is ReentrancyGuard, Pausable {
    // ─────────────────────────────────────────────────────────────────────────
    // Custom errors
    // ─────────────────────────────────────────────────────────────────────────

    error ZeroBeneficiary();
    error ZeroAmount();
    error UnlockTooSoon();
    error LockNotFound();
    error NotBeneficiary();
    error NotDepositor();
    error NotMatured();
    error AlreadySettled();
    error GracePeriodNotElapsed();
    error ZeroRecipient();
    error BatchTooLarge();
    error AdminOnly();
    error ZeroWithdrawAmount();
    error InsufficientFees();
    error TransferFailed();
    error DirectETHRejected();

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Minimum offset from now for an unlock timestamp.
    uint64 public constant MIN_DELAY = 1 days;

    /// @notice After unlock + GRACE_PERIOD the depositor can reclaim.
    uint64 public constant GRACE_PERIOD = 7 days;

    /// @notice Protocol fee in basis points (50 bps = 0.5 %).
    uint256 public constant FEE_BPS = 50;

    /// @notice Maximum number of lock IDs in a single batchClaim call.
    uint256 public constant MAX_BATCH = 32;

    uint256 private constant BPS_DENOM = 10_000;

    // ─────────────────────────────────────────────────────────────────────────
    // Data structures
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev A single time-locked deposit.
    struct Lock {
        address depositor;   // who created and funded the lock
        address beneficiary; // who may claim after unlock
        uint128 amount;      // ETH locked (wei)
        uint64  unlockTime;  // UNIX timestamp after which funds can be claimed
        bool    claimed;     // true once beneficiary has claimed
        bool    reclaimed;   // true once depositor has reclaimed
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    address public immutable admin;

    /// @notice Monotonically increasing lock-ID counter (starts at 1).
    uint256 public nextId;

    /// @notice All locks by ID.
    mapping(uint256 => Lock) private _locks;

    /// @notice Ordered list of lock IDs created for each beneficiary (TLW-4).
    mapping(address => uint256[]) private _beneficiaryLocks;

    /// @notice Cumulative protocol fees not yet withdrawn (TLW-9).
    uint256 public accruedFees;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event LockCreated(
        uint256 indexed id,
        address indexed depositor,
        address indexed beneficiary,
        uint128 amount,
        uint64  unlockTime
    );

    event Claimed(
        uint256 indexed id,
        address indexed beneficiary,
        address recipient,
        uint256 payout,
        uint256 fee
    );

    event BatchClaimed(
        address indexed beneficiary,
        address recipient,
        uint256[] ids,
        uint256 totalPayout,
        uint256 totalFee
    );

    event Reclaimed(
        uint256 indexed id,
        address indexed depositor,
        uint256 amount
    );

    event FeesWithdrawn(address indexed to, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor() {
        admin = msg.sender;
        nextId = 1; // IDs start at 1; 0 is reserved as "not found"
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reject direct ETH  (TLW-2)
    // ─────────────────────────────────────────────────────────────────────────

    receive() external payable {
        revert DirectETHRejected();
    }

    fallback() external payable {
        revert DirectETHRejected();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lock creation  (TLW-1)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Create a new time-locked deposit.
     * @param  beneficiary  Address that may claim the funds after unlock.
     * @param  unlockTime   UNIX timestamp (must be >= block.timestamp + MIN_DELAY).
     * @return id           Unique lock identifier.
     *
     * Interactions: none — all ETH is held in this contract.
     */
    function createLock(address beneficiary, uint64 unlockTime)
        external
        payable
        whenNotPaused
        returns (uint256 id)
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (beneficiary == address(0)) revert ZeroBeneficiary();
        if (msg.value == 0)            revert ZeroAmount();
        if (unlockTime < block.timestamp + MIN_DELAY) revert UnlockTooSoon();

        // ── Effects ─────────────────────────────────────────────────────────
        id = nextId++;

        _locks[id] = Lock({
            depositor:   msg.sender,
            beneficiary: beneficiary,
            amount:      uint128(msg.value),
            unlockTime:  unlockTime,
            claimed:     false,
            reclaimed:   false
        });

        _beneficiaryLocks[beneficiary].push(id);

        emit LockCreated(id, msg.sender, beneficiary, uint128(msg.value), unlockTime);

        // ── Interactions ─────────────────────────────────────────────────────
        // none — ETH is already held by this contract via msg.value
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View helpers  (TLW-3, TLW-4)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Return the full Lock struct for a given ID.  (TLW-3)
     */
    function getLock(uint256 id) external view returns (Lock memory) {
        if (_locks[id].depositor == address(0)) revert LockNotFound();
        return _locks[id];
    }

    /**
     * @notice Return all lock IDs for a beneficiary without scanning storage. (TLW-4)
     */
    function getLockIds(address beneficiary) external view returns (uint256[] memory) {
        return _beneficiaryLocks[beneficiary];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Single claim  (TLW-5, TLW-6)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim a matured lock.
     * @param  id        The lock to claim.
     * @param  recipient Where to send the payout (address(0) → msg.sender).
     *
     * Only the beneficiary may call. Follows checks-effects-interactions.
     * A protocol fee is accrued internally; only the net amount is forwarded.
     */
    function claim(uint256 id, address recipient)
        external
        nonReentrant
        whenNotPaused
    {
        // ── Checks ──────────────────────────────────────────────────────────
        Lock storage lock = _requireClaimable(id);

        address to = recipient == address(0) ? msg.sender : recipient;

        // ── Effects ─────────────────────────────────────────────────────────
        lock.claimed = true;

        (uint256 fee, uint256 payout) = _splitFee(lock.amount);
        accruedFees += fee;

        emit Claimed(id, lock.beneficiary, to, payout, fee);

        // ── Interactions ─────────────────────────────────────────────────────
        _safeTransfer(to, payout);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reclaim  (TLW-7)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Reclaim funds for a lock that nobody claimed within the grace period.
     * @param  id  The lock to reclaim.
     *
     * Only the original depositor may call, and only after
     * lock.unlockTime + GRACE_PERIOD has elapsed without a claim.
     * Full amount is returned — no protocol fee on reclaim.
     */
    function reclaim(uint256 id)
        external
        nonReentrant
        whenNotPaused
    {
        // ── Checks ──────────────────────────────────────────────────────────
        Lock storage lock = _locks[id];
        if (lock.depositor == address(0))  revert LockNotFound();
        if (lock.depositor != msg.sender)  revert NotDepositor();
        if (lock.claimed || lock.reclaimed) revert AlreadySettled();
        if (block.timestamp < lock.unlockTime + GRACE_PERIOD) revert GracePeriodNotElapsed();

        uint256 amount = lock.amount;
        address depositor = lock.depositor;

        // ── Effects ─────────────────────────────────────────────────────────
        lock.reclaimed = true;

        emit Reclaimed(id, depositor, amount);

        // ── Interactions ─────────────────────────────────────────────────────
        _safeTransfer(depositor, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Batch claim  (TLW-8)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim up to MAX_BATCH matured locks in one transaction.
     * @param  ids       Array of lock IDs (must be ≤ MAX_BATCH).
     * @param  recipient Where to send the combined payout (address(0) → msg.sender).
     *
     * All state mutations happen BEFORE the single external transfer, satisfying
     * checks-effects-interactions for the batch as a whole.
     */
    function batchClaim(uint256[] calldata ids, address recipient)
        external
        nonReentrant
        whenNotPaused
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (ids.length > MAX_BATCH) revert BatchTooLarge();
        if (ids.length == 0) revert BatchTooLarge(); // nothing to do → revert

        address to = recipient == address(0) ? msg.sender : recipient;

        uint256 totalPayout;
        uint256 totalFee;

        // ── Effects (all IDs before any transfer) ────────────────────────────
        for (uint256 i; i < ids.length; ++i) {
            Lock storage lock = _requireClaimable(ids[i]);

            lock.claimed = true;

            (uint256 fee, uint256 payout) = _splitFee(lock.amount);
            totalFee    += fee;
            totalPayout += payout;
        }

        accruedFees += totalFee;

        emit BatchClaimed(msg.sender, to, ids, totalPayout, totalFee);

        // ── Interactions ─────────────────────────────────────────────────────
        _safeTransfer(to, totalPayout);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fee withdrawal  (TLW-10)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Withdraw accrued protocol fees to an arbitrary address.
     * @param  to     Recipient of the fees.
     * @param  amount Amount to withdraw (must be ≤ accruedFees).
     *
     * Admin-only. Follows checks-effects-interactions.
     */
    function withdrawFees(address to, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        // ── Checks ──────────────────────────────────────────────────────────
        if (msg.sender != admin)    revert AdminOnly();
        if (to == address(0))       revert ZeroRecipient();
        if (amount == 0)            revert ZeroWithdrawAmount();
        if (amount > accruedFees)   revert InsufficientFees();

        // ── Effects ─────────────────────────────────────────────────────────
        accruedFees -= amount;

        emit FeesWithdrawn(to, amount);

        // ── Interactions ─────────────────────────────────────────────────────
        _safeTransfer(to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause controls  (TLW-11)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Pause the contract. Admin only.
    function pause() external {
        if (msg.sender != admin) revert AdminOnly();
        _pause();
    }

    /// @notice Unpause the contract. Admin only.
    function unpause() external {
        if (msg.sender != admin) revert AdminOnly();
        _unpause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @dev  Validate that a lock exists, is owned by the caller (beneficiary),
     *       is past its unlock time, and has not been claimed or reclaimed.
     *       Returns a storage reference so callers can mutate it immediately.
     */
    function _requireClaimable(uint256 id) private view returns (Lock storage lock) {
        lock = _locks[id];
        if (lock.depositor == address(0))   revert LockNotFound();
        if (lock.beneficiary != msg.sender) revert NotBeneficiary();
        if (block.timestamp < lock.unlockTime) revert NotMatured();
        if (lock.claimed || lock.reclaimed)  revert AlreadySettled();
    }

    /**
     * @dev  Split `amount` into fee and net payout using FEE_BPS.
     */
    function _splitFee(uint128 amount)
        private
        pure
        returns (uint256 fee, uint256 payout)
    {
        fee    = (uint256(amount) * FEE_BPS) / BPS_DENOM;
        payout = uint256(amount) - fee;
    }

    /**
     * @dev  Low-level ETH transfer with success check.  (TLW-5, TLW-7, TLW-8, TLW-10)
     */
    function _safeTransfer(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
