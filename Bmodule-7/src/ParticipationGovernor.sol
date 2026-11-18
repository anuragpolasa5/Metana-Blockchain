// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from
    "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from
    "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ParticipationGovernor
/// @author Anurag
/// @notice On-chain governance for the Participation DAO.
///         Reads voting power from ParticipationToken (ERC20Votes).
///         All approved proposals execute through DAOTimelock.
/// @dev Implements DAO-2 (Timelock + Governor wired correctly),
///      DAO-6 (full proposal lifecycle: propose → vote → queue → execute),
///      DAO-7 (concrete proposal actions executed through this governor).
///
/// ─── Parameter Rationale ─────────────────────────────────────────────────────
///
///   votingDelay    = 7200 blocks  ≈ 1 day  @ 12 s/block
///     Rationale: gives holders time to delegate before the vote snapshot is taken.
///
///   votingPeriod   = 36000 blocks ≈ 5 days @ 12 s/block
///     Rationale: long enough for async global participation, short enough for urgency.
///
///   proposalThreshold = 5e18 tokens (5 PART)
///     Rationale: ~5 weekly check-ins or 1 meaningful contribution. Prevents spam
///     while remaining reachable for any consistently active participant.
///
///   quorumNumerator = 4  (4% of total supply)
///     Rationale: low initial quorum to bootstrap governance; can be raised later
///     via a governance proposal using updateQuorumNumerator().
///
/// ─── Snapshot Compatibility ──────────────────────────────────────────────────
///
///   ParticipationToken inherits IERC5805 (clock = block.number).
///   Snapshot strategy: erc20-votes pointing at the token address.
///   Delegation via delegate() / delegateBySig() — standard OZ interface.
///
contract ParticipationGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice 1 day in blocks (12 s/block average on mainnet / Sepolia).
    /// @dev DAO-6: Voting delay gives holders time to delegate before snapshot.
    uint48 public constant VOTING_DELAY_BLOCKS = 7200;

    /// @notice 5 days in blocks.
    /// @dev DAO-6: Voting period allows async global participation.
    uint32 public constant VOTING_PERIOD_BLOCKS = 36000;

    /// @notice 5 PART tokens required to create a proposal.
    /// @dev DAO-6: Threshold prevents spam while being reachable via consistent participation.
    uint256 public constant PROPOSAL_THRESHOLD_TOKENS = 5e18;

    /// @notice 4% of total supply required for quorum.
    /// @dev DAO-6: Low initial quorum to bootstrap governance when supply is small.
    uint256 public constant QUORUM_NUMERATOR = 4;

    // ─── Constructor ─────────────────────────────────────────────────────────

    /// @notice Deploys the ParticipationGovernor linked to the token and timelock.
    /// @dev DAO-2: Wires the Governor to read votes from ParticipationToken and execute via DAOTimelock.
    /// @param _token The IVotes-compatible ParticipationToken for reading voting power.
    /// @param _timelock The TimelockController that queued proposals execute through.
    constructor(IVotes _token, TimelockController _timelock)
        Governor("ParticipationGovernor")
        GovernorSettings(VOTING_DELAY_BLOCKS, VOTING_PERIOD_BLOCKS, PROPOSAL_THRESHOLD_TOKENS)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(QUORUM_NUMERATOR)
        GovernorTimelockControl(_timelock)
    {}

    // ─── Required overrides (diamond-inheritance resolution) ─────────────────

    /// @notice Returns the voting delay in blocks.
    /// @dev DAO-6: Delegates GovernorSettings for the delay value.
    /// @return The number of blocks between proposal creation and vote start.
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @notice Returns the voting period in blocks.
    /// @dev DAO-6: Delegates GovernorSettings for the period value.
    /// @return The number of blocks the vote remains open.
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @notice Returns the proposal threshold (minimum votes to create a proposal).
    /// @dev DAO-6: 5 PART tokens required — reachable via ~5 check-ins or 1 fund action.
    /// @return The minimum number of votes (in token decimals) needed to propose.
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @notice Returns the quorum required at a given block number.
    /// @dev DAO-6: 4% of total supply at the snapshot block.
    /// @param blockNumber The block number to calculate quorum for.
    /// @return The number of votes required for quorum.
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /// @notice Returns the state of a proposal.
    /// @dev DAO-6: Accounts for timelock queue/execution states.
    /// @param proposalId The ID of the proposal to query.
    /// @return The current ProposalState enum value.
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @notice Checks if a proposal needs to be queued before execution.
    /// @dev DAO-2: All proposals must go through the timelock queue.
    /// @param proposalId The ID of the proposal.
    /// @return True if the proposal must be queued (always true with timelock).
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @notice Queues proposal operations into the timelock.
    /// @dev DAO-2: Schedules the batch operation in the TimelockController.
    /// @param proposalId The proposal ID being queued.
    /// @param targets Array of target contract addresses.
    /// @param values Array of ETH values for each call.
    /// @param calldatas Array of encoded function calls.
    /// @param descriptionHash The keccak256 hash of the proposal description.
    /// @return The timestamp when the proposal becomes executable.
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @notice Executes proposal operations through the timelock.
    /// @dev DAO-6: Final step of the proposal lifecycle — executes after timelock delay.
    /// @param proposalId The proposal ID being executed.
    /// @param targets Array of target contract addresses.
    /// @param values Array of ETH values for each call.
    /// @param calldatas Array of encoded function calls.
    /// @param descriptionHash The keccak256 hash of the proposal description.
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @notice Cancels a proposal and its timelock operations.
    /// @dev DAO-6: Allows cancellation of proposals that haven't been executed yet.
    /// @param targets Array of target contract addresses.
    /// @param values Array of ETH values for each call.
    /// @param calldatas Array of encoded function calls.
    /// @param descriptionHash The keccak256 hash of the proposal description.
    /// @return The proposal ID that was cancelled.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @notice Returns the executor address (the timelock).
    /// @dev DAO-2: The timelock is the executor — all proposals execute through it.
    /// @return The address of the TimelockController.
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
