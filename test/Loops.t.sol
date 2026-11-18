// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Loops.sol";
import "../src/OptimizedLoops.sol";

/// @title Loops Gas Optimization Tests
/// @notice Verifies functional equivalence and measures gas savings
contract LoopsTest is Test {
    Loops public baseline;
    OptimizedLoops public optimized;

    function setUp() public {
        baseline = new Loops();
        optimized = new OptimizedLoops();
    }

    // ========== Functional Equivalence Tests ==========

    /// @notice Both contracts must return the same sum (55 = 1+2+...+10)
    function test_sumArray_correctness() public view {
        uint256 baselineResult = baseline.sumArray();
        uint256 optimizedResult = optimized.sumArray();

        assertEq(baselineResult, 55, "Baseline sum should be 55");
        assertEq(optimizedResult, 55, "Optimized sum should be 55");
        assertEq(baselineResult, optimizedResult, "Both must return same result");
    }

    /// @notice Both contracts must return the same max (10)
    function test_findMax_correctness() public view {
        uint256 baselineResult = baseline.findMax();
        uint256 optimizedResult = optimized.findMax();

        assertEq(baselineResult, 10, "Baseline max should be 10");
        assertEq(optimizedResult, 10, "Optimized max should be 10");
        assertEq(baselineResult, optimizedResult, "Both must return same result");
    }

    /// @notice Verify array was initialized correctly in both contracts
    function test_array_initialization() public view {
        for (uint256 i = 0; i < 10; i++) {
            assertEq(baseline.numbers(i), i + 1, "Baseline numbers[i] mismatch");
            assertEq(optimized.numbers(i), i + 1, "Optimized numbers[i] mismatch");
        }
    }

    // ========== Gas Comparison Tests ==========

    /// @notice Measure gas for baseline sumArray
    function test_gas_baseline_sumArray() public {
        uint256 gasBefore = gasleft();
        baseline.sumArray();
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        emit log_named_uint("Baseline sumArray gas", gasUsed);
    }

    /// @notice Measure gas for optimized sumArray
    function test_gas_optimized_sumArray() public {
        uint256 gasBefore = gasleft();
        optimized.sumArray();
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        emit log_named_uint("Optimized sumArray gas", gasUsed);
    }

    /// @notice Measure gas for baseline findMax
    function test_gas_baseline_findMax() public {
        uint256 gasBefore = gasleft();
        baseline.findMax();
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        emit log_named_uint("Baseline findMax gas", gasUsed);
    }

    /// @notice Measure gas for optimized findMax
    function test_gas_optimized_findMax() public {
        uint256 gasBefore = gasleft();
        optimized.findMax();
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        emit log_named_uint("Optimized findMax gas", gasUsed);
    }

    /// @notice Verify optimized version uses less gas than baseline for sumArray
    function test_optimized_cheaper_sumArray() public {
        uint256 gasBefore1 = gasleft();
        baseline.sumArray();
        uint256 gasAfter1 = gasleft();
        uint256 baselineGas = gasBefore1 - gasAfter1;

        uint256 gasBefore2 = gasleft();
        optimized.sumArray();
        uint256 gasAfter2 = gasleft();
        uint256 optimizedGas = gasBefore2 - gasAfter2;

        assertLt(optimizedGas, baselineGas, "Optimized should use less gas");
    }

    /// @notice Verify optimized version uses less gas than baseline for findMax
    function test_optimized_cheaper_findMax() public {
        uint256 gasBefore1 = gasleft();
        baseline.findMax();
        uint256 gasAfter1 = gasleft();
        uint256 baselineGas = gasBefore1 - gasAfter1;

        uint256 gasBefore2 = gasleft();
        optimized.findMax();
        uint256 gasAfter2 = gasleft();
        uint256 optimizedGas = gasBefore2 - gasAfter2;

        assertLt(optimizedGas, baselineGas, "Optimized should use less gas");
    }
}
