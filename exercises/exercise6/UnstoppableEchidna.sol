// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DamnValuableToken.sol";
import "./UnstoppableLender.sol";
import "./ReceiverUnstoppable.sol";

/// @title UnstoppableEchidna - Echidna Exercise 6: Unstoppable Lender
/// @author Trail of Bits / Damn Vulnerable DeFi (Echidna Exercise)
/// @notice Tests that the UnstoppableLender can always provide flash loans.
/// @dev EX6-02: Setup: Pool is funded with 1,000,000 DVT tokens via depositTokens().
///      The bug: If someone sends tokens directly to the pool (via ERC20 transfer
///      instead of depositTokens), the internal poolBalance accounting diverges
///      from the actual token balance, causing the assert to fail permanently.
///      Fix: Replace `assert(poolBalance == balanceBefore)` with a >= check,
///      or remove it and rely on actual balance throughout.
contract UnstoppableEchidna {
    /// @notice The DVT token instance
    DamnValuableToken token;

    /// @notice The lending pool instance
    UnstoppableLender pool;

    /// @notice Sets up the test environment with funded pool
    /// @dev EX6-02: Deploys token and pool, funds pool with 1M tokens.
    ///      Also transfers 100 ether worth of tokens to the Echidna caller (msg.sender)
    ///      so the fuzzer can trigger the bug by sending tokens directly to the pool.
    constructor() {
        // Deploy token (mints max supply to this contract)
        token = new DamnValuableToken();

        // Deploy pool
        pool = new UnstoppableLender(address(token));

        // EX6-02: Fund the pool with 1,000,000 tokens via proper depositTokens method
        token.approve(address(pool), 1000000 ether);
        pool.depositTokens(1000000 ether);

        // EX6-02: Give the Echidna caller tokens so they can send directly to pool (the exploit)
        token.transfer(msg.sender, 100 ether);
    }

    /// @notice Callback for receiving flash loan tokens
    /// @dev Returns all borrowed tokens back to the pool
    /// @param tokenAddress The address of the token being returned
    /// @param amount The amount to return
    function receiveTokens(address tokenAddress, uint256 amount) external {
        require(
            IERC20(tokenAddress).transfer(msg.sender, amount),
            "Transfer failed"
        );
    }

    /// @notice Echidna property: flash loans should always be possible
    /// @dev EX6-02: This will FAIL when Echidna discovers it can call token.transfer()
    ///      directly to the pool address, breaking the poolBalance == actualBalance assertion.
    /// @return true if flash loan succeeds, false/revert if DoS achieved
    function echidna_test_flash_loan() public returns (bool) {
        // Try to execute a flash loan for 10 tokens
        pool.flashLoan(10);
        return true;
    }
}
