// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BatchCallDelegation7702} from "./BatchCallDelegation7702.sol";
import {IAccount, IAccountExecute, UserOperation} from "./interfaces/IAccount.sol";

// BA-1: Implement BatchCallDelegation4337 that inherits BatchCallDelegation7702, IAccount, and IAccountExecute
/**
 * @title BatchCallDelegation4337
 * @author Anurag
 * @notice Extends BatchCallDelegation7702 with ERC-4337 account abstraction support.
 *         Implements IAccount and IAccountExecute for compatibility with the EntryPoint contract.
 * @dev This contract serves as a smart contract account that can be controlled via
 *      UserOperations submitted through an EntryPoint. It validates operations and
 *      decodes batched calls from the UserOp callData field.
 */
contract BatchCallDelegation4337 is BatchCallDelegation7702, IAccount, IAccountExecute {
    /// @notice The trusted EntryPoint contract address that can call validation and execution.
    address public entryPoint;

    /// @notice The owner of this account (used for validation).
    address public owner;

    /// @notice Reverted when a caller other than the EntryPoint tries to invoke restricted functions.
    error NotEntryPoint();

    /// @dev Restricts function access to the EntryPoint contract only.
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert NotEntryPoint();
        _;
    }

    /**
     * @notice Initializes the account with an EntryPoint and owner.
     * @param _entryPoint The address of the trusted EntryPoint contract.
     * @param _owner The address of the account owner (used in validation).
     */
    constructor(address _entryPoint, address _owner) {
        entryPoint = _entryPoint;
        owner = _owner;
    }

    // BA-1: Implement validateUserOp
    /**
     * @notice Validates a user operation before execution.
     * @dev Checks that the userOp.sender matches this account's address.
     *      In a production implementation, this would verify a cryptographic signature
     *      against the userOpHash. Only callable by the EntryPoint.
     * @param userOp The user operation to validate.
     * @param userOpHash The hash of the user operation (for signature verification).
     * @param missingAccountFunds The amount of funds the account must deposit to the EntryPoint.
     * @return validationData 0 if the operation is valid, 1 if invalid.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        (userOpHash); // silence unused warning

        // Validate that the operation is intended for this account
        if (userOp.sender != address(this)) {
            return 1; // invalid
        }

        // Pay prefund to EntryPoint if needed
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            (success); // ignore failure (entrypoint will revert if deposit is insufficient)
        }

        return 0; // valid
    }

    // BA-1: executeUserOp decodes calls[] and forwards to execute()
    /**
     * @notice Executes a user operation by decoding calls from callData and forwarding to internal execute.
     * @dev Decodes an array of Call structs from userOp.callData and executes them sequentially.
     *      Only callable by the EntryPoint after successful validation.
     * @param userOp The user operation containing ABI-encoded Call[] in its callData field.
     * @param userOpHash The hash of the user operation (unused in execution).
     */
    function executeUserOp(UserOperation calldata userOp, bytes32 userOpHash) external onlyEntryPoint {
        (userOpHash); // silence unused variable warning

        // Decode the calls array from userOp.callData
        Call[] memory calls = abi.decode(userOp.callData, (Call[]));
        _executeInternal(calls);
    }

    /**
     * @notice Internal execute function that works with memory arrays.
     * @dev Mirrors the logic of execute() but accepts memory arrays (needed for decoded UserOp data).
     * @param calls Array of Call structs to execute sequentially.
     */
    function _executeInternal(Call[] memory calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory returnData) = calls[i].to.call{value: calls[i].value}(calls[i].data);
            if (!success) {
                revert CallFailed(i, returnData);
            }
            emit CallExecuted(i, calls[i].to, calls[i].value, calls[i].data);
        }
    }
}
