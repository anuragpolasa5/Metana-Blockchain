// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";

/// @title FlashLoanReceiver
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A contract that can receive flash loans from NaiveReceiverLenderPool.
/// @dev EX5-02: Vulnerability - receiveEther does not verify who initiated the flash loan.
///      Anyone can trigger a flash loan on behalf of this contract, causing it to pay
///      the 1 ETH fee repeatedly until its balance is drained.
///      Fix: Add an `initiator` parameter or restrict who can trigger loans for this contract.
contract FlashLoanReceiver {
    using Address for address payable;

    /// @notice The pool address this receiver interacts with
    address payable private pool;

    /// @notice Initializes the receiver with its associated pool
    /// @param poolAddress The address of the NaiveReceiverLenderPool
    constructor(address payable poolAddress) {
        pool = poolAddress;
    }

    /// @notice Callback function called by the pool during a flash loan
    /// @dev EX5-02: This function only checks msg.sender == pool, but does NOT check
    ///      who originally called flashLoan(). This is the root cause of the vulnerability.
    /// @param fee The fee that must be paid back to the pool
    function receiveEther(uint256 fee) public payable {
        require(msg.sender == address(pool), "Sender must be pool");

        uint256 amountToBeRepaid = msg.value + fee;

        require(
            address(this).balance >= amountToBeRepaid,
            "Cannot borrow that much"
        );

        _executeActionDuringFlashLoan();

        // Return funds to pool
        pool.sendValue(amountToBeRepaid);
    }

    /// @notice Internal function where the receiver would use the flash loan
    /// @dev Placeholder for actual flash loan logic
    function _executeActionDuringFlashLoan() internal {}

    /// @notice Allows this contract to receive ETH deposits
    receive() external payable {}
}
