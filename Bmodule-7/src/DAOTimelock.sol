// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DAOTimelock
/// @author Anurag
/// @notice Thin wrapper around OpenZeppelin's TimelockController for the Participation DAO.
/// @dev DAO-2: Timelock wired correctly with Governor as sole proposer and open executor.
///      DAO-8: 2-day minimum delay provides grace period for token holders to react.
///
/// Configuration rationale:
///   minDelay  = 2 days  – Grace period for token holders to detect and react to malicious proposals.
///   proposers = [governor] – Only the Governor may queue proposals.
///   executors = [address(0)] – Anyone can trigger execution after the delay (permissionless keeper).
///   admin     = deployer – DEFAULT_ADMIN_ROLE held by deployer initially; revoked post-setup
///               (or transferred to the Timelock itself for fully decentralised operation).
///
/// The Timelock is the owner of Treasury (holds TIMELOCK_ROLE) so only proposals that pass
/// governance can move funds or update parameters.
contract DAOTimelock is TimelockController {
    /// @notice Deploys the DAOTimelock with the specified delay, roles, and admin.
    /// @dev DAO-2: The Timelock acts as the bridge between Governor voting and Treasury execution.
    /// @param minDelay Minimum delay in seconds before a queued operation can be executed (2 days).
    /// @param proposers Array of addresses allowed to propose (should be [governor] after wiring).
    /// @param executors Array of addresses allowed to execute (address(0) = open executor).
    /// @param admin Initial admin address (revoked post-deploy to achieve full decentralisation).
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
