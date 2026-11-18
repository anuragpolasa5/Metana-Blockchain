// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {ParticipationToken} from "../src/ParticipationToken.sol";
import {EarnerModule} from "../src/EarnerModule.sol";
import {Treasury} from "../src/Treasury.sol";
import {DAOTimelock} from "../src/DAOTimelock.sol";
import {ParticipationGovernor} from "../src/ParticipationGovernor.sol";

/// @title Deploy
/// @author Anurag
/// @notice Deploys the full Participation DAO stack to a testnet.
/// @dev DAO-10: Complete deployment script with proper wiring of all roles.
///
/// Usage:
///   forge script script/Deploy.s.sol \
///     --rpc-url $RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $ETHERSCAN_API_KEY
///
/// After deployment, record addresses in docs/snapshot.md
contract Deploy is Script {
    // ─── Config ───────────────────────────────────────────────────────────────

    /// @dev Admin delay for AccessControlDefaultAdminRules (0 for testnet speed).
    uint48 constant ADMIN_DELAY = 0;

    /// @dev TimelockController minimum delay (2 days grace period).
    uint256 constant TIMELOCK_MIN_DELAY = 2 days;

    /// @notice Executes the full deployment sequence.
    /// @dev Deploys all 5 contracts, grants roles, and wires the governance stack.
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== Participation DAO Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        // ── 1. DAO-1: Deploy Participation Token ──────────────────────────────
        ParticipationToken token = new ParticipationToken(deployer, ADMIN_DELAY);
        console.log("ParticipationToken:", address(token));

        // ── 2. DAO-2: Deploy Timelock (proposers/executors set after governor) ─
        address[] memory emptyArr = new address[](0);
        DAOTimelock timelock = new DAOTimelock(TIMELOCK_MIN_DELAY, emptyArr, emptyArr, deployer);
        console.log("DAOTimelock:", address(timelock));

        // ── 3. DAO-3: Deploy Treasury (timelock gets TIMELOCK_ROLE) ───────────
        Treasury treasury = new Treasury(deployer, address(timelock));
        console.log("Treasury:", address(treasury));

        // ── 4. DAO-4: Deploy Earner Module ────────────────────────────────────
        EarnerModule earner = new EarnerModule(address(token), payable(address(treasury)), deployer);
        console.log("EarnerModule:", address(earner));

        // ── 5. DAO-1: Grant MINTER_ROLE to earner (sole minter) ───────────────
        token.grantRole(token.MINTER_ROLE(), address(earner));

        // ── 6. DAO-2: Deploy Governor ─────────────────────────────────────────
        ParticipationGovernor governor = new ParticipationGovernor(token, timelock);
        console.log("ParticipationGovernor:", address(governor));

        // ── 7. DAO-2: Wire timelock — governor = proposer, open executor ──────
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));   // open execution
        timelock.grantRole(cancellerRole, address(governor));

        // ── 8. DAO-8: Revoke deployer admin on timelock (full decentralisation) ─
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Record the following in docs/deployment.md:");
        console.log("  ParticipationToken:", address(token));
        console.log("  DAOTimelock:       ", address(timelock));
        console.log("  Treasury:          ", address(treasury));
        console.log("  EarnerModule:      ", address(earner));
        console.log("  Governor:          ", address(governor));
        console.log("\nSnapshot Strategy: erc20-votes");
        console.log("Token for Snapshot: ", address(token));
        console.log("Network: Sepolia (chainId 11155111)");
    }
}
