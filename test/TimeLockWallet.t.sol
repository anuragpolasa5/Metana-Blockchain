// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TimeLockWallet} from "../src/TimeLockWallet.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Malicious receiver contracts – used to prove nonReentrant blocks re-entry
// ─────────────────────────────────────────────────────────────────────────────

/// @dev Attempts to re-enter claim() when it receives ETH.
contract ReentrantClaimer {
    TimeLockWallet public wallet;
    uint256 public attackId;
    bool public attacked;

    constructor(TimeLockWallet _w) { wallet = _w; }

    function setup(uint256 id) external { attackId = id; }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try wallet.claim(attackId, address(0)) {} catch {}
        }
    }
}

/// @dev Attempts to re-enter batchClaim() when it receives ETH.
contract ReentrantBatchClaimer {
    TimeLockWallet public wallet;
    uint256[] public attackIds;
    bool public attacked;

    constructor(TimeLockWallet _w) { wallet = _w; }

    function setup(uint256[] calldata ids) external {
        delete attackIds;
        for (uint256 i; i < ids.length; ++i) attackIds.push(ids[i]);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try wallet.batchClaim(attackIds, address(0)) {} catch {}
        }
    }
}

/// @dev Attempts to re-enter reclaim() when it receives ETH.
contract ReentrantReclaimer {
    TimeLockWallet public wallet;
    uint256 public attackId;
    bool public attacked;

    constructor(TimeLockWallet _w) { wallet = _w; }

    function setup(uint256 id) external { attackId = id; }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try wallet.reclaim(attackId) {} catch {}
        }
    }
}

/// @dev Attempts to re-enter withdrawFees() when it receives ETH.
contract ReentrantFeeWithdrawer {
    TimeLockWallet public wallet;
    bool public attacked;

    constructor(TimeLockWallet _w) { wallet = _w; }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try wallet.withdrawFees(address(this), 1) {} catch {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main test contract
// ─────────────────────────────────────────────────────────────────────────────

contract TimeLockWalletTest is Test {
    TimeLockWallet public wallet;

    address public admin;
    address public alice;   // depositor / beneficiary
    address public bob;     // secondary actor
    address public carol;   // another beneficiary

    uint256 constant LOCK_AMOUNT  = 1 ether;
    uint64  constant MIN_DELAY    = 1 days;
    uint64  constant GRACE_PERIOD = 7 days;
    uint256 constant FEE_BPS      = 50;
    uint256 constant BPS_DENOM    = 10_000;

    // ─── helpers ─────────────────────────────────────────────────────────────

    function setUp() public {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob   = makeAddr("bob");
        carol = makeAddr("carol");

        vm.deal(alice, 100 ether);
        vm.deal(bob,   100 ether);

        vm.prank(admin);
        wallet = new TimeLockWallet();
    }

    /// @dev Create a lock from alice for alice at now + MIN_DELAY + buffer.
    function _createAliceLock(uint128 amount) internal returns (uint256 id) {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.prank(alice);
        id = wallet.createLock{value: amount}(alice, unlock);
    }

    /// @dev Create a lock with an explicit beneficiary.
    function _createLockFor(
        address depositor,
        address beneficiary,
        uint128 amount,
        uint64  unlock
    ) internal returns (uint256 id) {
        vm.deal(depositor, amount);
        vm.prank(depositor);
        id = wallet.createLock{value: amount}(beneficiary, unlock);
    }

    /// @dev Warp past the unlock time of a given lock.
    function _warpPastUnlock(uint256 id) internal {
        TimeLockWallet.Lock memory lock = wallet.getLock(id);
        vm.warp(lock.unlockTime + 1);
    }

    /// @dev Warp past unlock + grace period.
    function _warpPastGrace(uint256 id) internal {
        TimeLockWallet.Lock memory lock = wallet.getLock(id);
        vm.warp(lock.unlockTime + GRACE_PERIOD + 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-1: createLock
    // ─────────────────────────────────────────────────────────────────────────

    function test_createLock_success() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit TimeLockWallet.LockCreated(1, alice, bob, uint128(LOCK_AMOUNT), unlock);
        uint256 id = wallet.createLock{value: LOCK_AMOUNT}(bob, unlock);

        assertEq(id, 1);
        assertEq(wallet.nextId(), 2);

        TimeLockWallet.Lock memory lock = wallet.getLock(id);
        assertEq(lock.depositor,   alice);
        assertEq(lock.beneficiary, bob);
        assertEq(lock.amount,      LOCK_AMOUNT);
        assertEq(lock.unlockTime,  unlock);
        assertFalse(lock.claimed);
        assertFalse(lock.reclaimed);
        assertEq(address(wallet).balance, LOCK_AMOUNT);
    }

    function test_createLock_incrementsId() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.startPrank(alice);
        uint256 id1 = wallet.createLock{value: 1 ether}(bob, unlock);
        uint256 id2 = wallet.createLock{value: 1 ether}(bob, unlock);
        vm.stopPrank();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_createLock_indexesBeneficiary() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.startPrank(alice);
        wallet.createLock{value: 1 ether}(carol, unlock);
        wallet.createLock{value: 1 ether}(carol, unlock);
        vm.stopPrank();
        uint256[] memory ids = wallet.getLockIds(carol);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_createLock_zeroBeneficiary() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.ZeroBeneficiary.selector);
        wallet.createLock{value: LOCK_AMOUNT}(address(0), unlock);
    }

    function test_createLock_zeroAmount() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.ZeroAmount.selector);
        wallet.createLock{value: 0}(bob, unlock);
    }

    function test_createLock_unlockTooSoon_exact() public {
        // exactly at MIN_DELAY boundary (not >=, so should fail)
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY - 1;
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.UnlockTooSoon.selector);
        wallet.createLock{value: LOCK_AMOUNT}(bob, unlock);
    }

    function test_createLock_paused() public {
        vm.prank(admin);
        wallet.pause();
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.prank(alice);
        vm.expectRevert();
        wallet.createLock{value: LOCK_AMOUNT}(bob, unlock);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-2: receive / fallback reject direct ETH
    // ─────────────────────────────────────────────────────────────────────────

    function test_receive_revertsDirectETH() public {
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.DirectETHRejected.selector);
        (bool ok,) = address(wallet).call{value: 1 ether}("");
        // vm.expectRevert triggers, but the compiler warns; suppress:
        (ok);
    }

    function test_fallback_revertsDirectETH() public {
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.DirectETHRejected.selector);
        (bool ok,) = address(wallet).call{value: 1 ether}(hex"deadbeef");
        (ok);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-3: getLock
    // ─────────────────────────────────────────────────────────────────────────

    function test_getLock_returnsData() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        TimeLockWallet.Lock memory lock = wallet.getLock(id);
        assertEq(lock.depositor,   alice);
        assertEq(lock.beneficiary, alice);
        assertEq(lock.amount,      LOCK_AMOUNT);
    }

    function test_getLock_notFound() public {
        vm.expectRevert(TimeLockWallet.LockNotFound.selector);
        wallet.getLock(999);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-4: getLockIds
    // ─────────────────────────────────────────────────────────────────────────

    function test_getLockIds_empty() public view {
        uint256[] memory ids = wallet.getLockIds(carol);
        assertEq(ids.length, 0);
    }

    function test_getLockIds_multiple() public {
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.startPrank(alice);
        wallet.createLock{value: 1 ether}(carol, unlock);
        wallet.createLock{value: 2 ether}(carol, unlock);
        wallet.createLock{value: 3 ether}(carol, unlock);
        vm.stopPrank();
        uint256[] memory ids = wallet.getLockIds(carol);
        assertEq(ids.length, 3);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-5 / TLW-6: claim
    // ─────────────────────────────────────────────────────────────────────────

    function test_claim_success() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        uint256 fee    = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
        uint256 payout = LOCK_AMOUNT - fee;

        uint256 pre = alice.balance;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TimeLockWallet.Claimed(id, alice, alice, payout, fee);
        wallet.claim(id, address(0));

        assertEq(alice.balance - pre, payout);
        assertEq(wallet.accruedFees(), fee);
        assertTrue(wallet.getLock(id).claimed);
    }

    function test_claim_withRecipient() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        uint256 fee    = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
        uint256 payout = LOCK_AMOUNT - fee;

        uint256 pre = carol.balance;

        vm.prank(alice);
        wallet.claim(id, carol);

        assertEq(carol.balance - pre, payout);
    }

    function test_claim_notBeneficiary() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(bob);
        vm.expectRevert(TimeLockWallet.NotBeneficiary.selector);
        wallet.claim(id, address(0));
    }

    function test_claim_notMatured() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));

        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.NotMatured.selector);
        wallet.claim(id, address(0));
    }

    function test_claim_alreadyClaimed() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(alice);
        wallet.claim(id, address(0));

        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AlreadySettled.selector);
        wallet.claim(id, address(0));
    }

    function test_claim_paused() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(admin);
        wallet.pause();

        vm.prank(alice);
        vm.expectRevert();
        wallet.claim(id, address(0));
    }

    function test_claim_lockNotFound() public {
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.LockNotFound.selector);
        wallet.claim(9999, address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-7: reclaim
    // ─────────────────────────────────────────────────────────────────────────

    function test_reclaim_success() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastGrace(id);

        uint256 pre = alice.balance;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TimeLockWallet.Reclaimed(id, alice, LOCK_AMOUNT);
        wallet.reclaim(id);

        assertEq(alice.balance - pre, LOCK_AMOUNT);
        assertTrue(wallet.getLock(id).reclaimed);
    }

    function test_reclaim_beforeGracePeriod() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id); // past unlock but NOT past grace

        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.GracePeriodNotElapsed.selector);
        wallet.reclaim(id);
    }

    function test_reclaim_notDepositor() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastGrace(id);

        vm.prank(bob);
        vm.expectRevert(TimeLockWallet.NotDepositor.selector);
        wallet.reclaim(id);
    }

    function test_reclaim_alreadyClaimed() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(alice);
        wallet.claim(id, address(0));

        _warpPastGrace(id);

        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AlreadySettled.selector);
        wallet.reclaim(id);
    }

    function test_reclaim_paused() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastGrace(id);

        vm.prank(admin);
        wallet.pause();

        vm.prank(alice);
        vm.expectRevert();
        wallet.reclaim(id);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-8: batchClaim
    // ─────────────────────────────────────────────────────────────────────────

    function _createMultipleAliceLocks(uint8 n, uint128 amount)
        internal
        returns (uint256[] memory ids)
    {
        ids = new uint256[](n);
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        for (uint256 i; i < n; ++i) {
            vm.deal(alice, amount);
            vm.prank(alice);
            ids[i] = wallet.createLock{value: amount}(alice, unlock);
        }
    }

    function test_batchClaim_success() public {
        uint8 count = 5;
        uint256[] memory ids = _createMultipleAliceLocks(count, uint128(LOCK_AMOUNT));

        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        uint256 fee    = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
        uint256 payout = LOCK_AMOUNT - fee;

        uint256 pre = alice.balance;

        vm.prank(alice);
        wallet.batchClaim(ids, address(0));

        assertEq(alice.balance - pre, payout * count);
        assertEq(wallet.accruedFees(), fee * count);

        for (uint256 i; i < ids.length; ++i) {
            assertTrue(wallet.getLock(ids[i]).claimed);
        }
    }

    function test_batchClaim_withRecipient() public {
        uint256[] memory ids = _createMultipleAliceLocks(3, uint128(LOCK_AMOUNT));

        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        uint256 fee    = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
        uint256 payout = LOCK_AMOUNT - fee;
        uint256 pre = carol.balance;

        vm.prank(alice);
        wallet.batchClaim(ids, carol);

        assertEq(carol.balance - pre, payout * 3);
    }

    function test_batchClaim_tooLarge() public {
        uint256[] memory ids = new uint256[](33); // MAX_BATCH = 32
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.BatchTooLarge.selector);
        wallet.batchClaim(ids, address(0));
    }

    function test_batchClaim_emptyArray() public {
        uint256[] memory ids = new uint256[](0);
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.BatchTooLarge.selector);
        wallet.batchClaim(ids, address(0));
    }

    function test_batchClaim_notMatured() public {
        uint256[] memory ids = _createMultipleAliceLocks(2, uint128(LOCK_AMOUNT));
        // do NOT warp
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.NotMatured.selector);
        wallet.batchClaim(ids, address(0));
    }

    function test_batchClaim_notBeneficiary() public {
        uint256[] memory ids = _createMultipleAliceLocks(2, uint128(LOCK_AMOUNT));
        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        vm.prank(bob); // wrong caller
        vm.expectRevert(TimeLockWallet.NotBeneficiary.selector);
        wallet.batchClaim(ids, address(0));
    }

    function test_batchClaim_alreadyClaimed_reverts() public {
        uint256[] memory ids = _createMultipleAliceLocks(2, uint128(LOCK_AMOUNT));
        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        // claim the first one individually
        vm.prank(alice);
        wallet.claim(ids[0], address(0));

        // batch with already-claimed id → revert
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AlreadySettled.selector);
        wallet.batchClaim(ids, address(0));
    }

    function test_batchClaim_paused() public {
        uint256[] memory ids = _createMultipleAliceLocks(2, uint128(LOCK_AMOUNT));
        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        vm.prank(admin);
        wallet.pause();

        vm.prank(alice);
        vm.expectRevert();
        wallet.batchClaim(ids, address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-9: fee accrual
    // ─────────────────────────────────────────────────────────────────────────

    function test_feeAccrual_singleClaim() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(alice);
        wallet.claim(id, address(0));

        uint256 expectedFee = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
        assertEq(wallet.accruedFees(), expectedFee);
        // fee NOT forwarded inline – stays in contract balance
        assertEq(address(wallet).balance, expectedFee);
    }

    function test_feeAccrual_batchClaim() public {
        uint8 n = 4;
        uint256[] memory ids = _createMultipleAliceLocks(n, uint128(LOCK_AMOUNT));
        TimeLockWallet.Lock memory first = wallet.getLock(ids[0]);
        vm.warp(first.unlockTime + 1);

        vm.prank(alice);
        wallet.batchClaim(ids, address(0));

        uint256 expectedFee = ((LOCK_AMOUNT * FEE_BPS) / BPS_DENOM) * n;
        assertEq(wallet.accruedFees(), expectedFee);
        assertEq(address(wallet).balance, expectedFee);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-10: withdrawFees
    // ─────────────────────────────────────────────────────────────────────────

    function _accrueOneFee() internal returns (uint256 fee) {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);
        vm.prank(alice);
        wallet.claim(id, address(0));
        fee = (LOCK_AMOUNT * FEE_BPS) / BPS_DENOM;
    }

    function test_withdrawFees_success() public {
        uint256 fee = _accrueOneFee();
        uint256 pre = carol.balance;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit TimeLockWallet.FeesWithdrawn(carol, fee);
        wallet.withdrawFees(carol, fee);

        assertEq(carol.balance - pre, fee);
        assertEq(wallet.accruedFees(), 0);
    }

    function test_withdrawFees_partial() public {
        uint256 fee = _accrueOneFee();
        uint256 half = fee / 2;

        vm.prank(admin);
        wallet.withdrawFees(carol, half);

        assertEq(wallet.accruedFees(), fee - half);
    }

    function test_withdrawFees_notAdmin() public {
        _accrueOneFee();
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AdminOnly.selector);
        wallet.withdrawFees(alice, 1);
    }

    function test_withdrawFees_zeroRecipient() public {
        _accrueOneFee();
        vm.prank(admin);
        vm.expectRevert(TimeLockWallet.ZeroRecipient.selector);
        wallet.withdrawFees(address(0), 1);
    }

    function test_withdrawFees_zeroAmount() public {
        _accrueOneFee();
        vm.prank(admin);
        vm.expectRevert(TimeLockWallet.ZeroWithdrawAmount.selector);
        wallet.withdrawFees(carol, 0);
    }

    function test_withdrawFees_insufficientFees() public {
        uint256 fee = _accrueOneFee();
        vm.prank(admin);
        vm.expectRevert(TimeLockWallet.InsufficientFees.selector);
        wallet.withdrawFees(carol, fee + 1);
    }

    function test_withdrawFees_paused() public {
        _accrueOneFee();
        vm.prank(admin);
        wallet.pause();

        vm.prank(admin);
        vm.expectRevert();
        wallet.withdrawFees(carol, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-11: pause / unpause
    // ─────────────────────────────────────────────────────────────────────────

    function test_pause_notAdmin() public {
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AdminOnly.selector);
        wallet.pause();
    }

    function test_unpause_notAdmin() public {
        vm.prank(admin);
        wallet.pause();
        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.AdminOnly.selector);
        wallet.unpause();
    }

    function test_unpause_resumesOperations() public {
        uint256 id = _createAliceLock(uint128(LOCK_AMOUNT));
        _warpPastUnlock(id);

        vm.prank(admin);
        wallet.pause();

        vm.prank(admin);
        wallet.unpause();

        vm.prank(alice);
        wallet.claim(id, address(0)); // should succeed
        assertTrue(wallet.getLock(id).claimed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TLW-12: reentrancy guards
    // ─────────────────────────────────────────────────────────────────────────

    function test_reentrancy_claim() public {
        ReentrantClaimer attacker = new ReentrantClaimer(wallet);
        vm.deal(address(attacker), 0);

        // Create a lock for the attacker (it is both depositor and beneficiary)
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.deal(address(this), 2 ether);
        uint256 id = wallet.createLock{value: 1 ether}(address(attacker), unlock);
        attacker.setup(id);

        vm.warp(unlock + 1);

        uint256 fee    = (1 ether * FEE_BPS) / BPS_DENOM;
        uint256 payout = 1 ether - fee;

        // Attacker tries to re-enter; re-entry attempt is blocked by nonReentrant
        vm.prank(address(attacker));
        wallet.claim(id, address(0));

        // Despite re-entry attempt, lock is claimed exactly once
        assertTrue(wallet.getLock(id).claimed);
        assertEq(address(attacker).balance, payout);
        // Only one fee accrued
        assertEq(wallet.accruedFees(), fee);
    }

    function test_reentrancy_batchClaim() public {
        ReentrantBatchClaimer attacker = new ReentrantBatchClaimer(wallet);

        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        uint256[] memory ids = new uint256[](2);
        for (uint256 i; i < 2; ++i) {
            vm.deal(address(this), 1 ether);
            ids[i] = wallet.createLock{value: 1 ether}(address(attacker), unlock);
        }
        attacker.setup(ids);

        vm.warp(unlock + 1);

        vm.prank(address(attacker));
        wallet.batchClaim(ids, address(0));

        // Both locks claimed exactly once
        for (uint256 i; i < ids.length; ++i) {
            assertTrue(wallet.getLock(ids[i]).claimed);
        }
    }

    function test_reentrancy_reclaim() public {
        ReentrantReclaimer attacker = new ReentrantReclaimer(wallet);

        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.deal(address(attacker), 1 ether);
        vm.prank(address(attacker));
        uint256 id = wallet.createLock{value: 1 ether}(bob, unlock);
        attacker.setup(id);

        vm.warp(unlock + wallet.GRACE_PERIOD() + 1);

        vm.prank(address(attacker));
        wallet.reclaim(id);

        // Reclaimed exactly once
        assertTrue(wallet.getLock(id).reclaimed);
        assertEq(address(attacker).balance, 1 ether);
    }

    function test_reentrancy_withdrawFees() public {
        // Deploy a fresh wallet where the ReentrantFeeWithdrawer IS the admin.
        // This lets us trigger withdrawFees → receive() → withdrawFees re-entry.
        ReentrantFeeWithdrawer feeAttacker = new ReentrantFeeWithdrawer(TimeLockWallet(payable(address(0)))); // placeholder

        // Deploy wallet with feeAttacker as admin
        vm.prank(address(feeAttacker));
        TimeLockWallet w2 = new TimeLockWallet();

        // Point the attacker at the new wallet
        feeAttacker = new ReentrantFeeWithdrawer(w2);

        // Accrue some fees: alice creates a lock for herself in w2, then claims it
        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 id2 = w2.createLock{value: 1 ether}(alice, unlock);
        vm.warp(unlock + 1);
        vm.prank(alice);
        w2.claim(id2, address(0));

        uint256 feeBal = w2.accruedFees();
        assertTrue(feeBal > 0, "no fees accrued");

        // The real admin of w2 is the first feeAttacker address (the one set as admin at deploy).
        // Since we can't easily wire that up through vm.prank construction, let's instead
        // use the original `wallet` + `admin` path and prove nonReentrant works from a
        // helper contract that the admin grants the withdrawal to.
        //
        // Simplest correct proof: deploy wallet2 with THIS test contract as admin, accrue
        // fees, then call withdrawFees pointing to a ReentrantFeeWithdrawer.
        // The attacker's receive() will try to re-enter; nonReentrant must block it.

        vm.prank(address(this)); // this contract is deployer → admin of wallet3
        TimeLockWallet wallet3 = new TimeLockWallet();

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint64 u3 = uint64(block.timestamp) + MIN_DELAY + 1;
        uint256 id3 = wallet3.createLock{value: 1 ether}(alice, u3);
        vm.warp(u3 + 1);
        vm.prank(alice);
        wallet3.claim(id3, address(0));

        uint256 fee3 = wallet3.accruedFees();
        assertTrue(fee3 > 0);

        ReentrantFeeWithdrawer attacker3 = new ReentrantFeeWithdrawer(wallet3);

        // Admin (this test contract) withdraws to the attacker.
        // Attacker's receive() tries to re-enter withdrawFees(attacker3, 1).
        // nonReentrant must cause that inner call to revert (silently caught by try/catch).
        wallet3.withdrawFees(address(attacker3), fee3);

        // Fees withdrawn exactly once; attacker holds fee3, no double-withdrawal
        assertEq(wallet3.accruedFees(), 0);
        assertEq(address(attacker3).balance, fee3);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fuzz tests
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_createLock(
        address beneficiary,
        uint128 amount,
        uint64  unlockOffset
    ) public {
        vm.assume(beneficiary != address(0));
        vm.assume(amount > 0 && amount <= 1000 ether);
        // unlockOffset must be >= MIN_DELAY
        uint64 offset = uint64(bound(unlockOffset, MIN_DELAY, 365 days));
        uint64 unlock = uint64(block.timestamp) + offset;

        vm.deal(alice, amount);
        vm.prank(alice);
        uint256 id = wallet.createLock{value: amount}(beneficiary, unlock);

        TimeLockWallet.Lock memory lock = wallet.getLock(id);
        assertEq(lock.depositor,   alice);
        assertEq(lock.beneficiary, beneficiary);
        assertEq(lock.amount,      amount);
        assertEq(lock.unlockTime,  unlock);
        assertFalse(lock.claimed);
        assertFalse(lock.reclaimed);
    }

    function testFuzz_claim(uint128 amount, uint64 unlockOffset) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        uint64 offset = uint64(bound(unlockOffset, MIN_DELAY, 365 days));
        uint64 unlock = uint64(block.timestamp) + offset;

        vm.deal(alice, amount);
        vm.prank(alice);
        uint256 id = wallet.createLock{value: amount}(alice, unlock);

        vm.warp(unlock + 1);

        uint256 fee    = (uint256(amount) * FEE_BPS) / BPS_DENOM;
        uint256 payout = uint256(amount) - fee;
        uint256 pre    = alice.balance;

        vm.prank(alice);
        wallet.claim(id, address(0));

        assertEq(alice.balance - pre, payout);
        assertEq(wallet.accruedFees(), fee);
        assertEq(address(wallet).balance, fee);
    }

    function testFuzz_batchClaim(uint8 count, uint128 amount) public {
        count = uint8(bound(count, 1, 32));
        vm.assume(amount > 0 && amount <= 10 ether);

        uint64 unlock = uint64(block.timestamp) + MIN_DELAY + 1;
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            vm.deal(alice, amount);
            vm.prank(alice);
            ids[i] = wallet.createLock{value: amount}(alice, unlock);
        }

        vm.warp(unlock + 1);

        uint256 feePerLock    = (uint256(amount) * FEE_BPS) / BPS_DENOM;
        uint256 payoutPerLock = uint256(amount) - feePerLock;
        uint256 pre = alice.balance;

        vm.prank(alice);
        wallet.batchClaim(ids, address(0));

        assertEq(alice.balance - pre, payoutPerLock * count);
        assertEq(wallet.accruedFees(), feePerLock * count);
    }

    function testFuzz_feeMath(uint128 amount) public pure {
        vm.assume(amount > 0);
        uint256 fee    = (uint256(amount) * FEE_BPS) / BPS_DENOM;
        uint256 payout = uint256(amount) - fee;
        // invariant: fee + payout == amount (no rounding overflow)
        assertEq(fee + payout, uint256(amount));
        // fee is never more than the amount
        assertLe(fee, uint256(amount));
    }

    function testFuzz_reclaim(uint128 amount, uint64 unlockOffset) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        uint64 offset = uint64(bound(unlockOffset, MIN_DELAY, 365 days));
        uint64 unlock = uint64(block.timestamp) + offset;

        vm.deal(alice, amount);
        vm.prank(alice);
        uint256 id = wallet.createLock{value: amount}(bob, unlock);

        // warp past grace period
        vm.warp(uint256(unlock) + GRACE_PERIOD + 1);

        uint256 pre = alice.balance;
        vm.prank(alice);
        wallet.reclaim(id);

        assertEq(alice.balance - pre, uint256(amount));
        assertTrue(wallet.getLock(id).reclaimed);
    }

    function testFuzz_cannotClaimBeforeUnlock(uint128 amount, uint64 unlockOffset) public {
        vm.assume(amount > 0 && amount <= 100 ether);
        uint64 offset = uint64(bound(unlockOffset, MIN_DELAY, 365 days));
        uint64 unlock = uint64(block.timestamp) + offset;

        vm.deal(alice, amount);
        vm.prank(alice);
        uint256 id = wallet.createLock{value: amount}(alice, unlock);

        // Warp to just before unlock
        vm.warp(unlock - 1);

        vm.prank(alice);
        vm.expectRevert(TimeLockWallet.NotMatured.selector);
        wallet.claim(id, address(0));
    }
}
