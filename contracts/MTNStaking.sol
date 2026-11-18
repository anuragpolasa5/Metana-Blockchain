// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MTNStaking
/// @author Anurag
/// @notice Single-token staking contract using Synthetix-style reward distribution.
///         Users stake MTN and earn MTN rewards proportional to their stake and duration.
/// @dev Implements the Synthetix reward-per-token formula:
///      rewardPerTokenStored + (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate / totalSupply
///      Per-user tracking:
///      rewards[account] += balanceOf(account) * (rewardPerToken - userRewardPerTokenPaid[account]) / 1e18
contract MTNStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========

    /// @dev Thrown when the staking token address is the zero address.
    error ZeroAddress();
    /// @dev Thrown when staking a zero amount.
    error CannotStakeZero();
    /// @dev Thrown when withdrawing a zero amount.
    error CannotWithdrawZero();
    /// @dev Thrown when withdrawing more than the staked balance.
    error InsufficientBalance();
    /// @dev Thrown when the configured reward exceeds the funded balance.
    error RewardTooHigh();

    /// @notice The ERC20 token used for both staking and rewards (MTN).
    IERC20 public stakingToken;

    /// @notice Rate of reward tokens distributed per second.
    uint256 public rewardRate;

    /// @notice Duration over which rewards are distributed (default 7 days).
    uint256 public rewardsDuration = 7 days;

    /// @notice Timestamp when the current reward period ends.
    uint256 public periodFinish;

    /// @notice Last time reward accounting was updated.
    uint256 public lastUpdateTime;

    /// @notice Accumulated reward per token, scaled by 1e18.
    uint256 public rewardPerTokenStored;

    /// @notice Per-user snapshot of rewardPerToken at last interaction.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Per-user accumulated rewards not yet claimed.
    mapping(address => uint256) public rewards;

    /// @dev Total amount of tokens staked across all users.
    uint256 private _totalSupply;

    /// @dev Per-user staked balance.
    mapping(address => uint256) private _balances;

    // ========== EVENTS ==========

    /// @notice Emitted when a user stakes tokens.
    /// @param user The address that staked.
    /// @param amount The amount staked.
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws staked tokens.
    /// @param user The address that withdrew.
    /// @param amount The amount withdrawn.
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims their accumulated rewards.
    /// @param user The address that claimed.
    /// @param reward The reward amount paid out.
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Emitted when new rewards are added to the pool.
    /// @param reward The total reward amount added.
    event RewardAdded(uint256 reward);

    /// @notice Deploys the staking contract with the specified staking token.
    /// @param _stakingToken Address of the ERC20 token to be staked (MTN).
    constructor(address _stakingToken) Ownable(msg.sender) {
        if (_stakingToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
    }

    // ========== VIEWS ==========

    /// @notice Returns the total amount of tokens staked.
    /// @return The total supply of staked tokens.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns the staked balance of a specific account.
    /// @param account The address to query.
    /// @return The staked balance of the account.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Returns the last timestamp at which rewards are applicable.
    /// @dev Returns min(block.timestamp, periodFinish).
    /// @return The applicable timestamp for reward calculation.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Calculates the current reward per token using Synthetix formula.
    /// @dev Formula: rewardPerTokenStored + (elapsed * rewardRate * 1e18) / totalSupply
    /// @return The current reward per token value, scaled by 1e18.
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) /
            _totalSupply;
    }

    /// @notice Calculates how much reward a user has earned so far.
    /// @dev Formula: balance * (rewardPerToken - userPaid) / 1e18 + rewards[account]
    /// @param account The address to calculate earned rewards for.
    /// @return The total earned (unclaimed) reward for the account.
    function earned(address account) public view returns (uint256) {
        return
            (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    // ========== MUTATIVE FUNCTIONS ==========

    /// @notice Stake tokens to start earning rewards.
    /// @dev Transfers tokens from caller to this contract and updates reward state.
    /// @param amount The amount of tokens to stake. Must be > 0.
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert CannotStakeZero();
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw staked tokens (does not claim rewards).
    /// @dev Reduces user balance and total supply, transfers tokens back.
    /// @param amount The amount of tokens to withdraw. Must be > 0 and <= user balance.
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert CannotWithdrawZero();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim all accumulated rewards for the caller.
    /// @dev Transfers earned reward tokens to the caller and resets their reward balance.
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            stakingToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Withdraw all staked tokens and claim all rewards in one transaction.
    /// @dev Convenience function combining withdraw(full balance) + getReward().
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    // ========== ADMIN ==========

    /// @notice Fund the reward pool and set reward parameters.
    /// @dev Called by the owner (DepositContract) to start/extend a reward period.
    ///      Requires that the contract holds enough tokens to cover the reward at the new rate.
    /// @param reward The total amount of reward tokens to distribute over rewardsDuration.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the contract has enough tokens to cover the reward
        uint256 balance = stakingToken.balanceOf(address(this));
        if (rewardRate > balance / rewardsDuration) revert RewardTooHigh();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    // ========== MODIFIERS ==========

    /// @dev Updates reward accounting before executing the function body.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}
