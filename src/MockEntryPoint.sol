// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {IAccount, IAccountExecute, UserOperation} from "./interfaces/IAccount.sol";

// BA-2: Implement MockEntryPoint that inherits IEntryPoint and implements handleOps
/**
 * @title MockEntryPoint
 * @author Anurag
 * @notice A mock EntryPoint contract for testing ERC-4337 account abstraction.
 *         Implements handleOps by calling validateUserOp and then executeUserOp on each account.
 * @dev This is a simplified EntryPoint for testing purposes. It does not implement gas accounting,
 *      stake management, or aggregator logic. For each UserOperation, it:
 *      1. Calls validateUserOp on the account
 *      2. If validation passes (returns 0), calls executeUserOp
 *      3. Reverts if validation fails
 */
contract MockEntryPoint is IEntryPoint {
    /// @notice Emitted when a user operation is successfully handled (validated + executed).
    /// @param sender The account that executed the operation.
    /// @param index The index of the operation in the batch.
    event UserOpHandled(address indexed sender, uint256 indexed index);

    /// @notice Reverted when a user operation fails validation.
    /// @param index The index of the failed operation.
    error ValidationFailed(uint256 index);

    /// @notice Allows the EntryPoint to receive ETH (e.g., prefund from accounts).
    receive() external payable {}

    // BA-2: handleOps(UserOperation[] calldata ops) - for each action: call validateUserOp, if ok call executeUserOp
    /**
     * @notice Handles an array of user operations by validating and executing each one.
     * @dev For each operation in the array:
     *      1. Generates a mock userOpHash from sender, nonce, and callData
     *      2. Calls validateUserOp on the sender account
     *      3. If validation returns non-zero, reverts with ValidationFailed
     *      4. If validation passes, calls executeUserOp on the sender account
     * @param ops Array of user operations to process sequentially.
     * @param beneficiary Address to receive gas refunds (unused in this mock implementation).
     */
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external override {
        (beneficiary); // silence unused variable warning

        for (uint256 i = 0; i < ops.length; i++) {
            UserOperation calldata op = ops[i];
            address account = op.sender;

            // Generate a mock userOpHash for validation
            bytes32 userOpHash = keccak256(abi.encode(op.sender, op.nonce, op.callData));

            // BA-2: Step 1 - Call validateUserOp
            uint256 validationData = IAccount(account).validateUserOp(op, userOpHash, 0);

            // BA-2: If validation fails, revert
            if (validationData != 0) {
                revert ValidationFailed(i);
            }

            // BA-2: Step 2 - If ok, call executeUserOp
            IAccountExecute(account).executeUserOp(op, userOpHash);

            emit UserOpHandled(account, i);
        }
    }
}
