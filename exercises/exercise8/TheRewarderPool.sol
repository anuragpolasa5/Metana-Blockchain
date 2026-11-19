// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title RewardToken
/// @notice Token distributed as rewards by TheRewarderPool
contract RewardToken is ERC20 {
    /// @notice The address allowed to mint reward tokens
    address public minter;

    /// @notice Deploys the reward token and sets the minter
    constructor() ERC20("RewardToken", "RWT") {
        minter = msg.sender;
    }

    /// @notice Mints reward tokens to a recipient
    /// @dev Only callable by the minter (TheRewarderPool)
    /// @param to The recipient of the minted tokens
    /// @param amount The number of tokens to mint
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Only minter");
        _mint(to, amount);
    }
}

/// @title AccountingToken
/// @notice Token used for tracking deposits in TheRewarderPool
contract AccountingToken is ERC20 {
    /// @notice The address allowed to mint/burn accounting tokens
    address public minter;

    /// @notice Deploys the accounting token and sets the minter
    constructor() ERC20("AccountingToken", "ACT") {
        minter = msg.sender;
    }

    /// @notice Mints accounting tokens when a user deposits
    /// @param to The depositor's address
    /// @param amount The deposit amount to track
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "Only minter");
        _mint(to, amount);
    }

    /// @notice Burns accounting tokens when a user withdraws
    /// @param from The withdrawer's address
    /// @param amount The withdrawal amount to untrack
    function burn(address from, uint256 amount) external {
        require(msg.sender == minter, "Only minter");
        _burn(from, amount);
    }
}

/// @title TheRewarderPool
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A reward pool that distributes rewards proportionally to depositors.
/// @dev EX8-02: Vulnerability - An attacker can use a flash loan to deposit a large amount
///      just before rewards are distributed, claim almost all rewards (proportional to their
///      deposit vs total deposits), then withdraw and repay the flash loan.
///      The naive reward calculation doesn't account for deposit duration (time-weighted).
///      Fix: Implement time-weighted deposit tracking (e.g., snapshot-based or continuous accrual).
contract TheRewarderPool {
    /// @notice The token that users deposit for rewards
    IERC20 public immutable liquidityToken;

    /// @notice Token tracking user deposits
    AccountingToken public accToken;

    /// @notice Token distributed as rewards
    RewardToken public rewardToken;

    /// @notice Timestamp of the last reward distribution
    uint256 public lastRewardTimestamp;

    /// @notice Duration between reward rounds (5 days)
    uint256 public constant REWARDS_ROUND_DURATION = 5 days;

    /// @notice Amount of rewards distributed per round (100 tokens)
    uint256 public constant REWARDS_AMOUNT = 100 ether;

    /// @notice Tracks when each address last claimed rewards
    mapping(address => uint256) public lastRewardTimestamps;

    /// @notice Initializes the pool with the liquidity token and deploys helper tokens
    /// @param _liquidityToken The address of the token users deposit
    constructor(address _liquidityToken) {
        liquidityToken = IERC20(_liquidityToken);
        accToken = new AccountingToken();
        rewardToken = new RewardToken();
        lastRewardTimestamp = block.timestamp;
    }

    /// @notice Deposits liquidity tokens and triggers reward distribution
    /// @dev EX8-02: The vulnerability - rewards are distributed based on current deposit
    ///      proportion, not time-weighted proportion. A flash loan depositor gets
    ///      rewarded equally to long-term depositors.
    /// @param amountToDeposit The amount of liquidity tokens to deposit
    function deposit(uint256 amountToDeposit) external {
        require(amountToDeposit > 0, "Must deposit tokens");

        accToken.mint(msg.sender, amountToDeposit);
        distributeRewards();

        require(
            liquidityToken.transferFrom(
                msg.sender,
                address(this),
                amountToDeposit
            )
        );
    }

    /// @notice Withdraws deposited liquidity tokens
    /// @param amountToWithdraw The amount to withdraw
    function withdraw(uint256 amountToWithdraw) external {
        accToken.burn(msg.sender, amountToWithdraw);
        require(liquidityToken.transfer(msg.sender, amountToWithdraw));
    }

    /// @notice Distributes rewards proportionally to current depositors
    /// @dev EX8-02: Reward calculation: (depositor_balance / total_supply) * REWARDS_AMOUNT.
    ///      This is exploitable because a flash loan depositor temporarily inflates their
    ///      proportion of total_supply to claim nearly all rewards.
    /// @return rewards The amount of rewards distributed to the caller
    function distributeRewards() public returns (uint256) {
        uint256 rewards = 0;

        if (_isNewRewardsRound()) {
            lastRewardTimestamp = block.timestamp;

            uint256 totalDeposits = accToken.totalSupply();
            if (totalDeposits > 0) {
                uint256 depositorBalance = accToken.balanceOf(msg.sender);
                rewards = (depositorBalance * REWARDS_AMOUNT) / totalDeposits;

                if (rewards > 0 && !_hasRetrievedReward(msg.sender)) {
                    rewardToken.mint(msg.sender, rewards);
                    lastRewardTimestamps[msg.sender] = block.timestamp;
                }
            }
        }
        return rewards;
    }

    /// @notice Checks if an account has already claimed this round's reward
    /// @param account The address to check
    /// @return true if already claimed
    function _hasRetrievedReward(address account) private view returns (bool) {
        return lastRewardTimestamps[account] >= lastRewardTimestamp;
    }

    /// @notice Checks if enough time has passed for a new reward round
    /// @return true if a new round should begin
    function _isNewRewardsRound() private view returns (bool) {
        return
            block.timestamp >= lastRewardTimestamp + REWARDS_ROUND_DURATION;
    }
}
