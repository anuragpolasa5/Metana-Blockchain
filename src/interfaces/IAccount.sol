// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title UserOperation
 * @notice Struct representing a user operation for ERC-4337 account abstraction.
 * @dev Contains all fields needed by an EntryPoint to validate and execute an operation
 *      on behalf of a smart contract account.
 */
struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

// BA-1: IAccount interface for validateUserOp
/**
 * @title IAccount
 * @notice Interface that ERC-4337 account contracts must implement.
 * @dev Defines the validateUserOp function called by the EntryPoint during validation phase.
 */
interface IAccount {
    /**
     * @notice Validates a user operation.
     * @param userOp The user operation to validate.
     * @param userOpHash The hash of the user operation (used for signature verification).
     * @param missingAccountFunds The amount of funds the account must pay to the EntryPoint.
     * @return validationData 0 for valid, 1 for invalid. Can also encode time-range validity.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}

// BA-1: IAccountExecute interface for executeUserOp
/**
 * @title IAccountExecute
 * @notice Interface for executing user operations on an account.
 * @dev Called by the EntryPoint after successful validation to perform the account's intended actions.
 */
interface IAccountExecute {
    /**
     * @notice Executes a validated user operation.
     * @param userOp The validated user operation to execute.
     * @param userOpHash The hash of the user operation.
     */
    function executeUserOp(UserOperation calldata userOp, bytes32 userOpHash) external;
}
