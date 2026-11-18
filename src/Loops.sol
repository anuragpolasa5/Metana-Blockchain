// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Unoptimized Loops Contract
/// @author Module 11 Submission
/// @notice Demonstrates common gas-inefficient loop patterns for comparison
/// @dev This contract intentionally uses anti-patterns to illustrate gas waste
contract Loops {
    uint256[] public numbers;

    constructor() {
        for (uint256 i = 0; i < 10; i++) {
            numbers.push(i + 1);
        }
    }

    /// @notice Sums all elements in the numbers array
    /// @dev UNOPTIMIZED - uses multiple gas anti-patterns for demonstration
    /// @return The sum of all elements in the array
    // GL-01: Baseline loop reads storage on every iteration (SLOAD per element)
    // GL-02: Baseline re-reads array length from storage each iteration
    // GL-03: Baseline initializes i = 0 explicitly (redundant, wastes gas)
    // GL-04: Baseline uses i++ (post-increment creates temp variable)
    // GL-05: Baseline has overflow checks on every arithmetic operation
    function sumArray() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            total += numbers[i];
        }
        return total;
    }

    /// @notice Finds the maximum element in the numbers array
    /// @dev UNOPTIMIZED - same anti-patterns as sumArray
    /// @return The maximum value found in the array
    // GL-06: Baseline reads numbers[i] from storage twice per iteration
    function findMax() public view returns (uint256) {
        uint256 max = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            if (numbers[i] > max) {
                max = numbers[i];
            }
        }
        return max;
    }
}
