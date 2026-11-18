// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ParticipationToken} from "../src/ParticipationToken.sol";
import {EarnerModule} from "../src/EarnerModule.sol";
import {Treasury} from "../src/Treasury.sol";
import {DAOTimelock} from "../src/DAOTimelock.sol";
import {ParticipationGovernor} from "../src/ParticipationGovernor.sol";

/// @title ParticipationDAO Full Lifecycle Test Suite
/// @notice Tests cover DAO-1 through DAO-8:
///         earn → delegate → propose → vote → queue → execute → verify state change
contract ParticipationDAOTest is Test {
    // ─── Actors ───────────────────────────────────────────────────────────────
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal grantee = makeAddr("grantee");

    // ─── Contracts ────────────────────────────────────────────────────────────
    ParticipationToken internal token;
    EarnerModule internal earner;
    Treasury internal treasury;
    DAOTimelock internal timelock;
    ParticipationGovernor internal governor;

    // ─── Constants ────────────────────────────────────────────────────────────
    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint256 internal constant ETH_FOR_TREASURY = 10 ether;

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        vm.startPrank(admin);

        // 1. Deploy token
        token = new ParticipationToken(admin, 0);

        // 2. Deploy timelock (proposers/executors set after governor is known)
        address[] memory emptyArr = new address[](0);
        timelock = new DAOTimelock(TIMELOCK_DELAY, emptyArr, emptyArr, admin);

        // 3. Deploy treasury (timelock is TIMELOCK_ROLE holder)
        treasury = new Treasury(admin, address(timelock));

        // 4. Deploy earner (token + treasury)
        earner = new EarnerModule(address(token), payable(address(treasury)), admin);

        // 5. Grant MINTER_ROLE to earner
        token.grantRole(token.MINTER_ROLE(), address(earner));

        // 6. Deploy governor
        governor = new ParticipationGovernor(token, timelock);

        // 7. Configure timelock: governor is sole proposer, anyone can execute
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0)); // open executor
        timelock.grantRole(cancellerRole, address(governor));

        // 8. Revoke deployer's timelock admin role (full decentralisation)
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), admin);

        vm.stopPrank();

        // Fund treasury with ETH for tests
        vm.deal(address(treasury), ETH_FOR_TREASURY);
        // Give actors some ETH for fund() calls
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
        vm.deal(carol, 5 ether);
    }

    // ─── DAO-1: Earning Voting Power via checkIn() ────────────────────────────

    function test_DAO1_CheckIn_GrantsOneToken() public {
        vm.prank(alice);
        earner.checkIn();
        assertEq(token.balanceOf(alice), 1e18, "checkIn should mint 1 token");
    }

    function test_DAO1_CheckIn_AutoDelegates() public {
        vm.prank(alice);
        earner.checkIn();
        // Auto-delegation in mint() means getVotes() should reflect balance
        assertEq(token.getVotes(alice), 1e18, "should be auto-delegated after mint");
    }

    function test_DAO1_CheckIn_RevertsIfDoubleClaimedSameEpoch() public {
        vm.prank(alice);
        earner.checkIn();
        vm.prank(alice);
        vm.expectRevert(EarnerModule.AlreadyClaimedCheckIn.selector);
        earner.checkIn();
    }

    function test_DAO1_CheckIn_AllowsNextEpoch() public {
        vm.prank(alice);
        earner.checkIn();
        // Advance one epoch
        vm.warp(block.timestamp + earner.EPOCH_DURATION());
        vm.prank(alice);
        earner.checkIn();
        assertEq(token.balanceOf(alice), 2e18, "should earn 2 tokens across 2 epochs");
    }

    // ─── DAO-1: Earning via fund() ────────────────────────────────────────────

    function test_DAO1_Fund_EarnsProportionalTokens() public {
        // 0.1 ETH → 0.1 * 100 = 10 tokens (hits user cap exactly)
        vm.prank(alice);
        earner.fund{value: 0.1 ether}();
        assertEq(token.balanceOf(alice), 10e18, "0.1 ETH should earn 10 tokens");
    }

    function test_DAO1_Fund_PartialAward_WhenNearUserCap() public {
        // First fund hits cap
        vm.prank(alice);
        earner.fund{value: 0.1 ether}();
        // Second fund should revert (cap reached)
        vm.prank(alice);
        vm.expectRevert(EarnerModule.UserFundingCapReached.selector);
        earner.fund{value: 0.01 ether}();
    }

    function test_DAO1_Fund_RevertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(EarnerModule.ZeroContribution.selector);
        earner.fund{value: 0}();
    }

    function test_DAO1_Fund_GlobalCapEnforced() public {
        // 10 users each fund 0.1 ETH → global cap of 100 tokens reached
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string(abi.encodePacked("funder", i)));
            vm.deal(user, 1 ether);
            vm.prank(user);
            earner.fund{value: 0.1 ether}();
        }
        // 11th user should hit global cap
        address extra = makeAddr("extra");
        vm.deal(extra, 1 ether);
        vm.prank(extra);
        vm.expectRevert(EarnerModule.GlobalFundingCapReached.selector);
        earner.fund{value: 0.01 ether}();
    }

    function test_DAO1_Fund_ETHForwardedToTreasury() public {
        uint256 beforeBal = address(treasury).balance;
        vm.prank(alice);
        earner.fund{value: 0.05 ether}();
        assertEq(address(treasury).balance, beforeBal + 0.05 ether, "ETH should land in treasury");
    }

    // ─── DAO-1: Events ────────────────────────────────────────────────────────

    function test_DAO1_Fund_EmitsPointsEarned() public {
        uint256 epoch = earner.currentEpoch();
        vm.expectEmit(true, true, false, false);
        emit EarnerModule.PointsEarned(alice, epoch, 0, EarnerModule.EarnAction.FUND);
        vm.prank(alice);
        earner.fund{value: 0.01 ether}();
    }

    function test_DAO1_CheckIn_EmitsPointsEarned() public {
        uint256 epoch = earner.currentEpoch();
        vm.expectEmit(true, true, false, false);
        emit EarnerModule.PointsEarned(alice, epoch, 0, EarnerModule.EarnAction.CHECKIN);
        vm.prank(alice);
        earner.checkIn();
    }

    // ─── DAO-4: Cap Views ─────────────────────────────────────────────────────

    function test_DAO4_RemainingUserCap_DecreasesAfterFund() public {
        assertEq(earner.remainingUserCap(alice), earner.FUNDING_USER_CAP());
        vm.prank(alice);
        earner.fund{value: 0.05 ether}();
        // 0.05 ETH * 100 = 5 tokens earned → 5 remaining
        assertEq(earner.remainingUserCap(alice), 5e18);
    }

    function test_DAO4_RemainingGlobalCap_DecreasesAfterFund() public {
        assertEq(earner.remainingGlobalCap(), earner.FUNDING_GLOBAL_CAP());
        vm.prank(alice);
        earner.fund{value: 0.05 ether}();
        assertEq(earner.remainingGlobalCap(), earner.FUNDING_GLOBAL_CAP() - 5e18);
    }

    // ─── DAO-5: Delegation ────────────────────────────────────────────────────

    function test_DAO5_DelegateToAnother() public {
        // Alice earns tokens, delegates to bob
        vm.prank(alice);
        earner.checkIn();
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 1e18, "bob should have alice's votes");
        assertEq(token.getVotes(alice), 0, "alice should have 0 votes after delegating away");
    }

    function test_DAO5_ClaimedCheckIn_View() public {
        uint256 epoch = earner.currentEpoch();
        assertFalse(earner.claimedCheckIn(alice, epoch));
        vm.prank(alice);
        earner.checkIn();
        assertTrue(earner.claimedCheckIn(alice, epoch));
    }

    // ─── DAO-8: Pause ─────────────────────────────────────────────────────────

    function test_DAO8_PauseBlocksCheckIn() public {
        vm.prank(admin);
        earner.pause();
        vm.prank(alice);
        vm.expectRevert();
        earner.checkIn();
    }

    function test_DAO8_PauseBlocksFund() public {
        vm.prank(admin);
        earner.pause();
        vm.prank(alice);
        vm.expectRevert();
        earner.fund{value: 0.01 ether}();
    }

    function test_DAO8_UnpauseRestoresEarning() public {
        vm.prank(admin);
        earner.pause();
        vm.prank(admin);
        earner.unpause();
        vm.prank(alice);
        earner.checkIn();
        assertEq(token.balanceOf(alice), 1e18);
    }

    // ─── DAO-3: Treasury Security ─────────────────────────────────────────────

    function test_DAO3_DirectReleaseReverts_IfNotTimelock() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.releaseETH(payable(alice), 1 ether);
    }

    function test_DAO3_SetParam_OnlyTimelock() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.setParam(keccak256("grantLimit"), 1e18);
    }

    // ─── DAO-6: Full Proposal Lifecycle ───────────────────────────────────────

    function _earnEnoughToPropose(address user) internal {
        // Need > proposalThreshold (5e18 = 5 tokens)
        // checkIn gives 1 token per epoch – do it across 6 epochs
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(block.timestamp + earner.EPOCH_DURATION() * i);
            vm.prank(user);
            try earner.checkIn() {} catch {}
        }
        // Top up via fund to definitely exceed threshold
        vm.deal(user, 1 ether);
        vm.prank(user);
        earner.fund{value: 0.05 ether}();
    }

    /// @notice Full lifecycle: earn → delegate → propose → vote → queue → execute
    function test_DAO6_FullProposalLifecycle_ReleaseETH() public {
        // ── 1. Earn points for alice (proposer) and bob (voter) ──────────────
        vm.prank(alice);
        earner.fund{value: 0.1 ether}();          // alice gets 10 tokens (cap)

        vm.prank(bob);
        earner.checkIn();                           // bob gets 1 token

        // Advance past epoch so voting power is snapshotted on next block
        vm.roll(block.number + 1);

        // ── 2. Verify alice has enough to propose ────────────────────────────
        assertGt(token.getVotes(alice), governor.proposalThreshold(), "alice needs > threshold");

        // ── 3. Build proposal calldata: releaseETH(grantee, 1 ether) ─────────
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "releaseETH(address,uint256)",
            payable(grantee),
            1 ether
        );
        string memory description = "Proposal #1: Release 1 ETH grant to grantee";

        // ── 4. Propose ───────────────────────────────────────────────────────
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Pending),
            "proposal should be pending"
        );

        // ── 5. Advance past votingDelay ──────────────────────────────────────
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Active),
            "proposal should be active"
        );

        // ── 6. Cast votes ────────────────────────────────────────────────────
        // Support = 1 = For
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // ── 7. Advance past votingPeriod ─────────────────────────────────────
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check quorum
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        console.log("For votes:", forVotes);
        console.log("Quorum required:", governor.quorum(block.number - 1));
        assertGt(forVotes, governor.quorum(block.number - 1), "quorum should be reached");

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Succeeded),
            "proposal should have succeeded"
        );

        // ── 8. Queue into timelock ────────────────────────────────────────────
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Queued),
            "proposal should be queued"
        );

        // ── 9. Advance past timelock delay ───────────────────────────────────
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // ── 10. Execute ───────────────────────────────────────────────────────
        uint256 granteeBefore = grantee.balance;
        uint256 treasuryBefore = address(treasury).balance;

        governor.execute(targets, values, calldatas, descriptionHash);

        // ── 11. Verify state change ───────────────────────────────────────────
        assertEq(grantee.balance, granteeBefore + 1 ether, "grantee should receive 1 ETH");
        assertEq(address(treasury).balance, treasuryBefore - 1 ether, "treasury should decrease by 1 ETH");
        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Executed),
            "proposal should be executed"
        );
    }

    // ─── DAO-7: setParam via Proposal ─────────────────────────────────────────

    function test_DAO7_SetParam_ViaGovernance() public {
        // Alice earns enough to propose
        vm.prank(alice);
        earner.fund{value: 0.1 ether}();
        vm.roll(block.number + 1);

        bytes32 paramKey = keccak256("grantLimit");
        uint256 paramValue = 50 ether;

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("setParam(bytes32,uint256)", paramKey, paramValue);
        string memory description = "Proposal #2: Set grantLimit to 50 ETH";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Vote → queue → execute
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        // Verify param was updated
        assertEq(treasury.params(paramKey), paramValue, "param should be updated");
    }

    // ─── DAO-6: Quorum Failure ────────────────────────────────────────────────

    function test_DAO6_ProposalDefeated_WhenQuorumNotReached() public {
        // Alice earns enough to propose but nobody votes for (or only small vote)
        vm.prank(alice);
        earner.fund{value: 0.1 ether}();
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("releaseETH(address,uint256)", payable(grantee), 1 ether);
        string memory description = "Proposal #3: Should fail (no quorum)";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        // Nobody votes – just let the period expire
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Should be Defeated (no votes cast, quorum not reached)
        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Defeated),
            "proposal with no votes should be defeated"
        );
    }

    // ─── DAO-2: Proposal Threshold Enforced ───────────────────────────────────

    function test_DAO2_ProposalRejected_IfBelowThreshold() public {
        // Carol has 0 tokens – cannot propose
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSignature("releaseETH(address,uint256)", payable(carol), 1 ether);

        vm.prank(carol);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Unauthorised proposal");
    }
}
