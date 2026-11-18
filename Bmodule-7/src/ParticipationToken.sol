// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title ParticipationToken
/// @author Anurag
/// @notice Non-transferable ERC20Votes token whose voting power is earned through
///         on-chain participation actions. Only the EarnerModule (MINTER_ROLE) can mint.
///         Delegation is fully supported for Snapshot compatibility (IERC5805 / EIP-6372).
/// @dev Implements DAO-1 (participation token with ERC20Votes + checkpoints),
///      DAO-5 (delegation support), DAO-8 (AccessControlDefaultAdminRules security),
///      and DAO-9 (Snapshot-compatible IERC5805 token with block-number clock).
///
/// Non-transferability design:
///   - _update() reverts unless from == address(0) (mint) or to == address(0) (burn).
///   - approve() / transferFrom() are therefore useless but left in ABI for ERC20 compliance.
///   - Delegation (delegate/delegateBySig) is unaffected because it does NOT call _update.
///
/// Voting power accounting:
///   - ERC20Votes uses clock() = block.number for snapshots.
///   - Each user must self-delegate (or delegate to another address) before votes are counted.
///   - The EarnerModule calls _delegate(to, to) after minting so new holders are auto-delegated.
contract ParticipationToken is ERC20, ERC20Permit, ERC20Votes, AccessControlDefaultAdminRules {
    /// @notice Role that permits minting. Granted exclusively to EarnerModule.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ─── Errors ──────────────────────────────────────────────────────────────

    /// @dev Raised when a non-mint / non-burn transfer is attempted.
    error TransfersDisabled();

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @notice Deploys the ParticipationToken with the specified admin and delay.
    /// @dev DAO-8: Uses AccessControlDefaultAdminRules for secure 2-step admin transfer.
    /// @param initialAdmin Address that receives DEFAULT_ADMIN_ROLE. Should be a
    ///        multisig or the deployer EOA during bootstrap.
    /// @param adminDelay Delay enforced before transferring DEFAULT_ADMIN_ROLE.
    constructor(address initialAdmin, uint48 adminDelay)
        ERC20("Participation Token", "PART")
        ERC20Permit("Participation Token")
        AccessControlDefaultAdminRules(adminDelay, initialAdmin)
    {}

    // ─── Minting ─────────────────────────────────────────────────────────────

    /// @notice Mint `amount` tokens to `to`. Restricted to MINTER_ROLE.
    /// @dev DAO-1: Only the EarnerModule (MINTER_ROLE) can mint participation tokens.
    ///      DAO-5: Auto-delegates to self on first mint so voting power is immediately active.
    /// @param to The address receiving the minted tokens.
    /// @param amount The number of tokens to mint (in 18-decimal wei units).
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        // DAO-5: Auto-delegate to self if not yet delegated (delegates returns address(0) initially)
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }
    }

    // ─── Non-transferability ─────────────────────────────────────────────────

    /// @notice Overrides the ERC20 transfer hook to enforce non-transferability.
    /// @dev DAO-1: PART tokens are non-transferable to prevent vote markets and vote buying.
    ///      Only mints (from == address(0)) and burns (to == address(0)) are allowed.
    /// @param from The sender address (address(0) for mints).
    /// @param to The recipient address (address(0) for burns).
    /// @param value The amount of tokens being moved.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (from != address(0) && to != address(0)) {
            revert TransfersDisabled();
        }
        super._update(from, to, value);
    }

    // ─── EIP-6372 clock (block-number based) ─────────────────────────────────

    /// @notice Returns the current clock value used for vote checkpointing.
    /// @dev DAO-9: Uses block.number as the clock for Snapshot compatibility (IERC5805).
    /// @return The current block number cast to uint48.
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Returns the machine-readable description of the clock mode.
    /// @dev DAO-9: Required by IERC6372 for Snapshot strategy detection.
    /// @return The clock mode string indicating block-number-based voting.
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    // ─── Nonces (required by both ERC20Permit and ERC20Votes) ────────────────

    /// @notice Returns the current nonce for the given owner (used by ERC20Permit and ERC20Votes).
    /// @dev Resolves the diamond inheritance conflict between ERC20Permit and Nonces.
    /// @param owner The address to query the nonce for.
    /// @return The current nonce value for `owner`.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
