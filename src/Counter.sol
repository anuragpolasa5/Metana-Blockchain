// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// BE-3: Deploy a simple Counter contract that increments a uint256 variable via increment()
/**
 * @title Counter
 * @author Anurag
 * @notice A simple counter contract used for testing batch call delegation.
 * @dev Provides a single increment() function that increases a uint256 state variable.
 *      Used as one of the batch actions in EIP-7702 and ERC-4337 testing.
 */
contract Counter {
    /// @notice The current counter value, starts at 0.
    uint256 public number;

    /// @notice Emitted when the counter is incremented.
    /// @param newNumber The new counter value after incrementing.
    event Incremented(uint256 newNumber);

    // BE-3: increment() function that increments the uint256 variable
    /**
     * @notice Increments the counter by 1.
     * @dev Can be called by any address. Emits Incremented event with the new value.
     */
    function increment() external {
        number++;
        emit Incremented(number);
    }
}
