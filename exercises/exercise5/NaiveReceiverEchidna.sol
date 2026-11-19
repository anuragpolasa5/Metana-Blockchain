// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./NaiveReceiverLenderPool.sol";
import "./FlashLoanReceiver.sol";

/// @title NaiveReceiverEchidna - Echidna Exercise 5: Naive Receiver
/// @author Trail of Bits / Damn Vulnerable DeFi (Echidna Exercise)
/// @notice Tests that the FlashLoanReceiver's balance cannot decrease.
/// @dev EX5-03: Setup mirrors the DeFi challenge: pool has 1000 ETH, receiver has 10 ETH.
///      The bug: anyone can call flashLoan(receiver, 0) repeatedly to drain
///      the receiver's balance through fee payments (1 ETH per call × 10 calls = drained).
///      Fix: The receiver should verify that the flash loan was initiated by an authorized party.
contract NaiveReceiverEchidna {
    /// @notice The flash loan pool instance
    NaiveReceiverLenderPool pool;

    /// @notice The vulnerable receiver instance
    FlashLoanReceiver receiver;

    /// @notice The initial balance of the receiver (10 ETH)
    uint256 initialReceiverBalance;

    /// @notice Sets up the test environment matching the DeFi challenge conditions
    /// @dev EX5-03: Deploys pool with 1000 ETH and receiver with 10 ETH
    constructor() payable {
        // Deploy the pool with 1000 ETH
        pool = new NaiveReceiverLenderPool();
        (bool success1, ) = address(pool).call{value: 1000 ether}("");
        require(success1);

        // Deploy the receiver with 10 ETH
        receiver = new FlashLoanReceiver(payable(address(pool)));
        (bool success2, ) = address(receiver).call{value: 10 ether}("");
        require(success2);

        initialReceiverBalance = address(receiver).balance;
    }

    /// @notice Echidna property: receiver balance should not decrease
    /// @dev EX5-03: This will FAIL because an attacker can call flashLoan(receiver, 0)
    ///      to force the receiver to pay the 1 ETH fee without the receiver's consent.
    /// @return true if receiver balance is preserved, false if drained
    function echidna_test_receiver_balance() public view returns (bool) {
        return address(receiver).balance >= initialReceiverBalance;
    }
}
