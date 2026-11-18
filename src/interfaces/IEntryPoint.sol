// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UserOperation} from "./IAccount.sol";

// BA-2: IEntryPoint interface with handleOps
/**
 * @title IEntryPoint
 * @notice Interface for the ERC-4337 EntryPoint contract.
 * @dev Defines the handleOps function that processes batches of UserOperations.
 */
interface IEntryPoint {
    /**
     * @notice Handles a batch of user operations.
     * @dev For each operation, the EntryPoint must validate via the account's validateUserOp,
     *      then execute via the account's executeUserOp.
     * @param ops Array of user operations to process.
     * @param beneficiary Address to receive gas compensation.
     */
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external;
}
