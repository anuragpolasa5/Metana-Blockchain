// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @notice Interface for flash loan receiver callback
interface IReceiver {
    function receiveTokens(address tokenAddress, uint256 amount) external;
}

/// @title UnstoppableLender
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A lending pool that provides flash loans of ERC20 tokens.
/// @dev EX6-01: Vulnerability - The assertion `poolBalance == balanceBefore` can be broken
///      by directly transferring tokens to the pool (bypassing depositTokens()).
///      This causes poolBalance (internal accounting) to differ from the actual
///      token balance, making flash loans permanently unavailable (DoS).
///      Fix: Remove the strict equality assertion or use actual balance for all checks.
contract UnstoppableLender is ReentrancyGuard {
    /// @notice The ERC20 token used for flash loans
    IERC20 public immutable damnValuableToken;

    /// @notice Internal accounting of the pool's token balance
    /// @dev EX6-01: This diverges from actual balance when tokens are sent directly
    uint256 public poolBalance;

    /// @notice Initializes the lender with the token to be lent
    /// @param tokenAddress The address of the ERC20 token
    constructor(address tokenAddress) {
        require(tokenAddress != address(0));
        damnValuableToken = IERC20(tokenAddress);
    }

    /// @notice Deposits tokens into the pool using the proper accounting method
    /// @dev Updates poolBalance to track deposits correctly
    /// @param amount The number of tokens to deposit
    function depositTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Must deposit at least one token");
        damnValuableToken.transferFrom(msg.sender, address(this), amount);
        poolBalance = poolBalance + amount;
    }

    /// @notice Executes a flash loan of the specified amount
    /// @dev EX6-01: The `assert(poolBalance == balanceBefore)` is the vulnerability.
    ///      If tokens are sent directly to this contract via ERC20.transfer() (not through
    ///      depositTokens), poolBalance stays unchanged while actual balance increases.
    ///      This assertion then permanently fails, making flash loans impossible.
    /// @param borrowAmount The number of tokens to borrow
    function flashLoan(uint256 borrowAmount) external nonReentrant {
        require(borrowAmount > 0, "Must borrow at least one token");

        uint256 balanceBefore = damnValuableToken.balanceOf(address(this));
        require(balanceBefore >= borrowAmount, "Not enough tokens in pool");

        // EX6-01: BUG - This assertion breaks if tokens are sent directly to contract
        assert(poolBalance == balanceBefore);

        damnValuableToken.transfer(msg.sender, borrowAmount);

        IReceiver(msg.sender).receiveTokens(
            address(damnValuableToken),
            borrowAmount
        );

        uint256 balanceAfter = damnValuableToken.balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore,
            "Flash loan hasn't been paid back"
        );
    }
}
