// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BatchCallDelegation7702
 * @author Anurag
 * @notice A contract that enables batch execution of multiple calls via EIP-7702 delegation.
 *         An EOA can delegate to this contract and execute multiple actions in a single transaction.
 * @dev This contract is designed to be used as a delegation target for EIP-7702.
 *      The EOA signs an authorization designating this contract, then sends a transaction
 *      calling execute() on itself to batch multiple operations atomically.
 */
contract BatchCallDelegation7702 {
    // BE-1: Struct Call { address to; uint256 value; bytes data; }
    /// @notice Represents a single call to be executed in a batch.
    /// @param to The target address for the call.
    /// @param value The amount of ETH (in wei) to send with the call.
    /// @param data The calldata to include with the call.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    // BE-1: Emits an event per call
    /// @notice Emitted when a single call within a batch is successfully executed.
    /// @param index The index of the call in the batch array.
    /// @param to The target address that was called.
    /// @param value The ETH value sent with the call.
    /// @param data The calldata that was sent.
    event CallExecuted(uint256 indexed index, address indexed to, uint256 value, bytes data);

    // BE-1: Reverts on failure
    /// @notice Reverted when a call in the batch fails.
    /// @param index The index of the failed call.
    /// @param returnData The return data from the failed call (contains revert reason).
    error CallFailed(uint256 index, bytes returnData);

    // BE-1: execute(Call[] calldata calls) function that iterates, executes low-level calls,
    //        reverts on failure, emits an event per call, and accepts ETH.
    /**
     * @notice Execute a batch of calls sequentially.
     * @dev Iterates through the calls array, executing each via low-level `call`.
     *      If any call fails, the entire transaction reverts with CallFailed error.
     *      Emits a CallExecuted event for each successful call.
     * @param calls Array of Call structs to execute in order.
     */
    function execute(Call[] calldata calls) public payable virtual {
        for (uint256 i = 0; i < calls.length; i++) {
            // Execute each call via low-level call with specified value and data
            (bool success, bytes memory returnData) = calls[i].to.call{value: calls[i].value}(calls[i].data);

            // BE-1: Reverts if any fail
            if (!success) {
                revert CallFailed(i, returnData);
            }

            // BE-1: Emits an event per call
            emit CallExecuted(i, calls[i].to, calls[i].value, calls[i].data);
        }
    }

    // BE-1: Accept and forward ETH
    /// @notice Allows the contract to receive ETH directly (needed for EIP-7702 delegation).
    receive() external payable {}
}
