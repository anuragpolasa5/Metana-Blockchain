// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/AlienFactory.sol";
import "../src/OptimizedAlienFactory.sol";

/// @title AlienFactory Gas Optimization Tests
/// @notice Verifies functional equivalence and measures gas savings
contract AlienFactoryTest is Test {
    AlienFactory public baseline;
    OptimizedAlienFactory public optimized;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        baseline = new AlienFactory();
        optimized = new OptimizedAlienFactory();
    }

    // ========== Functional Equivalence Tests ==========

    /// @notice Creating an alien should increment the count
    function test_createAlien_incrementsCount() public {
        vm.prank(alice);
        baseline.createAlien("Zorb", 100);
        assertEq(baseline.getAlienCount(), 1);

        vm.prank(alice);
        optimized.createAlien("Zorb", 100);
        assertEq(optimized.getAlienCount(), 1);
    }

    /// @notice Creating multiple aliens should track correctly
    function test_createMultipleAliens() public {
        vm.startPrank(alice);
        baseline.createAlien("Zorb", 100);
        baseline.createAlien("Xarg", 200);
        baseline.createAlien("Blip", 50);
        vm.stopPrank();

        assertEq(baseline.getAlienCount(), 3);
        assertEq(baseline.getOwnerAliens(alice).length, 3);

        vm.startPrank(alice);
        optimized.createAlien("Zorb", 100);
        optimized.createAlien("Xarg", 200);
        optimized.createAlien("Blip", 50);
        vm.stopPrank();

        assertEq(optimized.getAlienCount(), 3);
        assertEq(optimized.getOwnerAliens(alice).length, 3);
    }

    /// @notice Different owners should have separate alien lists
    function test_differentOwners() public {
        vm.prank(alice);
        baseline.createAlien("AliceAlien", 100);

        vm.prank(bob);
        baseline.createAlien("BobAlien", 200);

        assertEq(baseline.getOwnerAliens(alice).length, 1);
        assertEq(baseline.getOwnerAliens(bob).length, 1);
        assertEq(baseline.getAlienCount(), 2);

        vm.prank(alice);
        optimized.createAlien("AliceAlien", 100);

        vm.prank(bob);
        optimized.createAlien("BobAlien", 200);

        assertEq(optimized.getOwnerAliens(alice).length, 1);
        assertEq(optimized.getOwnerAliens(bob).length, 1);
        assertEq(optimized.getAlienCount(), 2);
    }

    /// @notice Created alien should have correct attributes
    function test_alienAttributes() public {
        vm.prank(alice);
        baseline.createAlien("TestAlien", 150);

        address alienAddr = baseline.getOwnerAliens(alice)[0];
        Alien alien = Alien(alienAddr);

        assertEq(alien.name(), "TestAlien");
        assertEq(alien.power(), 150);
        assertEq(alien.owner(), alice);
        assertTrue(alien.isAlive());
    }

    /// @notice Optimized alien should have correct attributes
    function test_optimizedAlienAttributes() public {
        vm.prank(alice);
        optimized.createAlien("TestAlien", 150);

        address alienAddr = optimized.getOwnerAliens(alice)[0];
        OptimizedAlien alien = OptimizedAlien(alienAddr);

        assertEq(alien.name(), "TestAlien");
        assertEq(alien.power(), 150);
        assertEq(alien.owner(), alice);
        assertTrue(alien.isAlive());
    }

    /// @notice Alien attack should return power when alive
    function test_alienAttack() public {
        vm.prank(alice);
        optimized.createAlien("Fighter", 999);

        address alienAddr = optimized.getOwnerAliens(alice)[0];
        OptimizedAlien alien = OptimizedAlien(alienAddr);

        assertEq(alien.attack(), 999);
    }

    /// @notice Event should be emitted on creation
    function test_emitsAlienCreated() public {
        vm.prank(alice);
        vm.expectEmit(false, true, false, false);
        emit OptimizedAlienFactory.AlienCreated(address(0), alice);
        optimized.createAlien("EventAlien", 42);
    }

    /// @notice Owner with no aliens should return empty array
    function test_noAliensForNewOwner() public view {
        assertEq(optimized.getOwnerAliens(alice).length, 0);
        assertEq(baseline.getOwnerAliens(alice).length, 0);
    }

    /// @notice Test with max uint64 power value (boundary for packed storage)
    function test_maxPowerValue() public {
        uint64 maxPower = type(uint64).max;
        vm.prank(alice);
        optimized.createAlien("MaxPower", maxPower);

        address alienAddr = optimized.getOwnerAliens(alice)[0];
        OptimizedAlien alien = OptimizedAlien(alienAddr);

        assertEq(alien.power(), maxPower);
    }

    /// @notice Test with empty name
    function test_emptyName() public {
        vm.prank(alice);
        optimized.createAlien("", 1);

        address alienAddr = optimized.getOwnerAliens(alice)[0];
        OptimizedAlien alien = OptimizedAlien(alienAddr);

        assertEq(alien.name(), "");
        assertEq(alien.power(), 1);
    }

    // ========== Gas Comparison Tests ==========

    /// @notice Measure gas for baseline createAlien
    function test_gas_baseline_createAlien() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        baseline.createAlien("GasTest", 100);
        uint256 gasAfter = gasleft();

        emit log_named_uint("Baseline createAlien gas", gasBefore - gasAfter);
    }

    /// @notice Measure gas for optimized createAlien
    function test_gas_optimized_createAlien() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        optimized.createAlien("GasTest", 100);
        uint256 gasAfter = gasleft();

        emit log_named_uint("Optimized createAlien gas", gasBefore - gasAfter);
    }

    /// @notice Verify optimized factory uses less gas
    function test_optimized_cheaper_createAlien() public {
        vm.prank(alice);
        uint256 gasBefore1 = gasleft();
        baseline.createAlien("GasComp", 100);
        uint256 gasAfter1 = gasleft();
        uint256 baselineGas = gasBefore1 - gasAfter1;

        vm.prank(bob);
        uint256 gasBefore2 = gasleft();
        optimized.createAlien("GasComp", 100);
        uint256 gasAfter2 = gasleft();
        uint256 optimizedGas = gasBefore2 - gasAfter2;

        assertLt(optimizedGas, baselineGas, "Optimized should use less gas");
    }
}
