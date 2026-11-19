// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Interface for flash loan callback
interface IFlashLoanReceiver {
    function receiveFlashLoan(uint256 amount) external;
}

/// @title FlashLoanerPool
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice Provides flash loans of the liquidity token.
/// @dev EX8-01: This pool provides the flash loan capability that enables the reward attack.
///      It lends tokens with the expectation they are returned within the same transaction.
contract FlashLoanerPool is ReentrancyGuard {
    /// @notice The token available for flash loans
    IERC20 public immutable liquidityToken;

    /// @notice Initializes the pool with the token to be lent
    /// @param liquidityTokenAddress The address of the ERC20 token for flash loans
    constructor(address liquidityTokenAddress) {
        liquidityToken = IERC20(liquidityTokenAddress);
    }

    /// @notice Executes a flash loan of the liquidity token
    /// @dev Transfers tokens to borrower, calls callback, verifies repayment
    /// @param amount The number of tokens to lend
    function flashLoan(uint256 amount) external nonReentrant {
        uint256 balanceBefore = liquidityToken.balanceOf(address(this));
        require(balanceBefore >= amount, "Not enough token balance");

        liquidityToken.transfer(msg.sender, amount);

        IFlashLoanReceiver(msg.sender).receiveFlashLoan(amount);

        require(
            liquidityToken.balanceOf(address(this)) >= balanceBefore,
            "Flash loan not paid back"
        );
    }
}
