// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Optimized Loops Contract
/// @author Module 11 Submission
/// @notice Gas-efficient loop implementations demonstrating key optimization patterns
/// @dev Each optimization is tagged with the requirement ID it addresses
contract OptimizedLoops {
    uint256[] public numbers;

    constructor() {
        for (uint256 i = 0; i < 10; i++) {
            numbers.push(i + 1);
        }
    }

    /// @notice Sums all elements in the numbers array with minimal gas usage
    /// @dev Applies 5 distinct optimizations vs the baseline implementation
    /// @return total The sum of all elements in the array
    // GL-01: Cache storage array in memory — single SLOAD for entire array instead of N SLOADs
    // GL-02: Cache array length in local variable — avoids repeated storage reads
    // GL-03: Skip explicit zero initialization — uint256 defaults to 0
    // GL-04: Use pre-increment ++i — avoids temporary variable allocation
    // GL-05: Use unchecked block — skips overflow checks on bounded loop counter
    function sumArray() public view returns (uint256 total) {
        uint256[] memory _numbers = numbers; // GL-01
        uint256 len = _numbers.length;       // GL-02
        for (uint256 i; i < len; ) {         // GL-03: no `= 0`
            total += _numbers[i];
            unchecked { ++i; }               // GL-04 + GL-05
        }
        // Named return variable saves an extra MSTORE operation
    }

    /// @notice Finds the maximum element in the numbers array with minimal gas usage
    /// @dev Caches storage reads and uses unchecked increment
    /// @return max The maximum value found in the array
    // GL-06: Cache element in local variable — avoids double storage/memory read
    function findMax() public view returns (uint256 max) {
        uint256[] memory _numbers = numbers; // GL-01: cache in memory
        uint256 len = _numbers.length;       // GL-02: cache length
        for (uint256 i; i < len; ) {         // GL-03: no zero init
            uint256 current = _numbers[i];   // GL-06: single read, reuse local
            if (current > max) {
                max = current;
            }
            unchecked { ++i; }               // GL-04 + GL-05
        }
    }
}
