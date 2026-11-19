// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";

/// @notice Interface for flash loan callback
interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

/// @title SideEntranceLenderPool
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A lending pool that allows ETH deposits, withdrawals, and flash loans.
/// @dev EX7-01: Vulnerability - During a flash loan, the borrower can call deposit()
///      with the borrowed funds. This satisfies the balance check (pool balance restored)
///      while crediting the borrower's internal balance. The borrower can then
///      call withdraw() after the flash loan completes to steal all pool funds.
///      Fix: Prevent deposit() from being called during flash loan execution,
///      or use a separate mechanism for flash loan repayment tracking.
contract SideEntranceLenderPool {
    using Address for address payable;

    /// @notice Internal balance tracking for depositors
    mapping(address => uint256) private balances;

    /// @notice Deposits ETH into the pool, crediting the sender's balance
    /// @dev EX7-01: This can be called during a flash loan callback,
    ///      which is the root cause of the vulnerability.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Withdraws the caller's entire deposited balance
    /// @dev EX7-01: After exploiting deposit() during a flash loan,
    ///      the attacker calls this to extract the stolen funds.
    function withdraw() external {
        uint256 amountToWithdraw = balances[msg.sender];
        balances[msg.sender] = 0;
        payable(msg.sender).sendValue(amountToWithdraw);
    }

    /// @notice Executes a flash loan, sending ETH to the borrower
    /// @dev EX7-01: The balance check only verifies total ETH balance is restored,
    ///      but doesn't track HOW it was restored. If restored via deposit(),
    ///      the borrower gains an internal balance they can later withdraw.
    /// @param amount The amount of ETH to lend
    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        require(balanceBefore >= amount, "Not enough ETH in balance");

        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        require(
            address(this).balance >= balanceBefore,
            "Flash loan hasn't been paid back"
        );
    }
}
