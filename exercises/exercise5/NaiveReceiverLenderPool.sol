// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title NaiveReceiverLenderPool
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A lending pool that offers flash loans with a fixed fee of 1 ETH.
/// @dev EX5-01: Vulnerability - anyone can call flashLoan on behalf of any borrower,
///      draining the borrower's funds through repeated fee payments of 1 ETH each.
///      The pool does not verify who initiated the flash loan request.
contract NaiveReceiverLenderPool is ReentrancyGuard {
    using Address for address;

    /// @notice The fixed fee charged for every flash loan (1 ETH)
    uint256 private constant FIXED_FEE = 1 ether;

    /// @notice Returns the fixed fee for flash loans
    /// @return The fee amount (1 ETH)
    function fixedFee() external pure returns (uint256) {
        return FIXED_FEE;
    }

    /// @notice Executes a flash loan to a borrower contract
    /// @dev EX5-01: The critical vulnerability is that `borrower` is caller-specified.
    ///      Anyone can force any contract to take a flash loan and pay the fee.
    ///      Fix: Only allow the borrower themselves to initiate their own flash loan.
    /// @param borrower The address of the contract receiving the flash loan
    /// @param borrowAmount The amount of ETH to lend
    function flashLoan(address borrower, uint256 borrowAmount) external nonReentrant {
        uint256 balanceBefore = address(this).balance;
        require(balanceBefore >= borrowAmount, "Not enough ETH in pool");

        require(borrower.isContract(), "Borrower must be a deployed contract");

        // EX5-01: Transfer ETH and call receiveEther on the borrower
        borrower.functionCallWithValue(
            abi.encodeWithSignature("receiveEther(uint256)", FIXED_FEE),
            borrowAmount
        );

        require(
            address(this).balance >= balanceBefore + FIXED_FEE,
            "Flash loan hasn't been paid back"
        );
    }

    /// @notice Allows the pool to receive ETH deposits
    receive() external payable {}
}
