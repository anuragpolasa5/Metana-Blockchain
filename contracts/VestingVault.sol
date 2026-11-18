// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./VestingToken.sol";

/// @title VestingVault – time-locked token vesting controller (pull-over-push).
/// @notice Admin creates per-beneficiary vesting schedules. Beneficiaries call
///         `claim()` to receive linearly-unlocked tokens. Nothing is pushed;
///         all transfers are initiated by the beneficiary.
contract VestingVault is AccessControl, ReentrancyGuard {
    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ─── State ────────────────────────────────────────────────────────────────
    /// @notice The ERC-20 token that this vault vests. Immutable after deployment.
    VestingToken public immutable token;

    struct Schedule {
        address beneficiary;
        uint64  cliff;        // delay (seconds) before any tokens unlock
        uint64  duration;     // seconds over which tokens vest *after* cliff
        uint256 totalAmount;
        uint256 claimedAmount;
        uint64  startTime;    // block.timestamp at schedule creation
    }

    uint256 public nextScheduleId;
    mapping(uint256 => Schedule) public schedules;

    // ─── Custom errors ────────────────────────────────────────────────────────
    error Unauthorized();
    error InvalidSchedule();
    error NothingToClaim();
    error ScheduleNotFound();
    error ZeroAdminAddress();
    error InvalidTokenAddress();

    // ─── Events ───────────────────────────────────────────────────────────────
    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount,
        uint64  cliff,
        uint64  duration
    );
    event Claimed(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount
    );

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(address tokenAddress, address admin) {
        if (admin == address(0)) revert ZeroAdminAddress();
        if (tokenAddress == address(0) || tokenAddress.code.length == 0)
            revert InvalidTokenAddress();
        token = VestingToken(tokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Create a vesting schedule for `beneficiary`.
    /// @param beneficiary Recipient of the vested tokens.
    /// @param cliff       Seconds after schedule creation before any tokens unlock.
    /// @param duration    Seconds over which the full amount vests (linear) once cliff passes.
    /// @param amount      Total token amount to vest (in wei).
    function createSchedule(
        address beneficiary,
        uint64  cliff,
        uint64  duration,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        if (
            beneficiary == address(0) ||
            duration == 0 ||
            amount == 0 ||
            uint256(block.timestamp) + uint256(cliff) > type(uint64).max
        ) {
            revert InvalidSchedule();
        }

        uint256 scheduleId = nextScheduleId;
        schedules[scheduleId] = Schedule({
            beneficiary:   beneficiary,
            cliff:         cliff,
            duration:      duration,
            totalAmount:   amount,
            claimedAmount: 0,
            startTime:     uint64(block.timestamp)
        });

        unchecked { nextScheduleId++; }   // safe: overflow in ~10^77 calls

        emit ScheduleCreated(scheduleId, beneficiary, amount, cliff, duration);
    }

    // ─── View helpers ─────────────────────────────────────────────────────────

    /// @notice Returns the total amount vested up to the current block for `scheduleId`.
    function vestedAmount(uint256 scheduleId) public view returns (uint256) {
        Schedule storage s = schedules[scheduleId];
        if (s.beneficiary == address(0)) revert ScheduleNotFound();

        uint64 cliffEnd = s.startTime + s.cliff;
        if (block.timestamp < cliffEnd) return 0;

        unchecked {
            uint256 elapsed = block.timestamp - cliffEnd;
            if (elapsed >= s.duration) return s.totalAmount;
            // Linear: safe because elapsed < duration <= type(uint64).max
            return (s.totalAmount * elapsed) / s.duration;
        }
    }

    /// @notice Returns how many tokens `scheduleId` can claim right now.
    function claimable(uint256 scheduleId) public view returns (uint256) {
        uint256 vested = vestedAmount(scheduleId);
        Schedule storage s = schedules[scheduleId];
        unchecked {
            return vested > s.claimedAmount ? vested - s.claimedAmount : 0;
        }
    }

    // ─── Beneficiary ──────────────────────────────────────────────────────────

    /// @notice Pull vested tokens. Reverts if nothing is claimable.
    /// @param scheduleId The schedule to claim from.
    function claim(uint256 scheduleId) external nonReentrant {
        Schedule storage s = schedules[scheduleId];
        if (s.beneficiary == address(0)) revert ScheduleNotFound();
        if (s.beneficiary != msg.sender) revert Unauthorized();

        uint256 amount = claimable(scheduleId);
        if (amount == 0) revert NothingToClaim();

        unchecked { s.claimedAmount += amount; }   // safe: <= totalAmount
        token.mint(msg.sender, amount);

        emit Claimed(scheduleId, msg.sender, amount);
    }
}