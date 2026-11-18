// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "solmate/src/tokens/ERC4626.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AutoCompoundingVault (aMTN)
/// @author Anurag
/// @notice ERC-4626 vault that accepts wMTN deposits and mints aMTN shares.
///         Rewards are streamed over REWARDS_DURATION (7 days) via notifyRewardAmount().
///         Inherits from solmate ERC4626: https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC4626.sol
/// @dev Users stake wMTN to receive aMTN (vault shares) representing proportional claim on strategy.
///      The vault tracks totalStaked separately from streamed rewards to enable time-weighted distribution.
contract AutoCompoundingVault is ERC4626, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    // ========== CUSTOM ERRORS ==========

    /// @dev Thrown when a deposit-contract-only function is called by another address.
    error OnlyDepositContract();
    /// @dev Thrown when the deposit contract address is the zero address.
    error DepositContractZero();
    /// @dev Thrown when notifyRewardAmount is called but there are no new rewards.
    error NoNewRewards();
    /// @dev Thrown when a deposit/withdraw is attempted with zero assets.
    error ZeroAssets();
    /// @dev Thrown when a mint/redeem is attempted with zero shares.
    error ZeroShares();
    /// @dev Thrown when the first deposit mints fewer shares than MINIMUM_LIQUIDITY.
    error InitialDepositBelowMinimum();

    // ========== STATE VARIABLES ==========

    /// @notice Address of the deposit contract (only caller allowed for notifyRewardAmount).
    address public depositContract;

    /// @notice Duration over which rewards are linearly streamed (7 days).
    uint256 public constant REWARDS_DURATION = 7 days;

    /// @notice Amount of shares permanently locked on the first deposit (inflation guard).
    /// @dev Mirrors the Uniswap-V2 "minimum liquidity" pattern: the first MINIMUM_LIQUIDITY
    ///      shares are sent to a dead address so totalSupply can never return to ~0. This
    ///      neutralises the classic ERC-4626 share-price inflation / donation attack, where an
    ///      attacker makes the first tiny deposit, donates assets to skew the exchange rate, and
    ///      forces later depositors' share amounts to round down to zero.
    uint256 public constant MINIMUM_LIQUIDITY = 1e3;

    /// @notice Address that holds the permanently-locked minimum-liquidity dead shares.
    address public constant DEAD_ADDRESS = address(0xdead);

    /// @dev True once the minimum-liquidity dead shares have been seeded on the first deposit.
    bool private _deadSharesSeeded;

    /// @notice Rate of reward tokens streamed per second.
    uint256 public rewardRate;

    /// @notice Timestamp when the current reward streaming period ends.
    uint256 public periodFinish;

    /// @notice Last time reward accounting was updated.
    uint256 public lastUpdateTime;

    /// @notice Total amount of staked wMTN tracked by the vault (excluding streaming rewards).
    uint256 public totalStaked;

    // ========== EVENTS ==========

    // DF-12: Emit events on deposit, withdrawal, and yield harvest
    /// @notice Emitted when new rewards are added and streaming begins.
    /// @param reward The amount of new rewards added.
    event RewardAdded(uint256 reward);

    /// @notice Emitted when earned rewards are harvested into totalStaked.
    /// @param amount The amount of rewards harvested.
    event Harvested(uint256 amount);

    /// @notice Emitted when the minimum-liquidity dead shares are locked on the first deposit.
    /// @param amount The amount of shares permanently locked at DEAD_ADDRESS.
    event DeadSharesSeeded(uint256 amount);

    // ========== MODIFIERS ==========

    // DF-4: Restrict certain functions to only be callable by the deposit contract
    /// @dev Restricts function access to the deposit contract only.
    modifier onlyDepositContract() {
        if (msg.sender != depositContract) revert OnlyDepositContract();
        _;
    }

    // ========== CONSTRUCTOR ==========

    /// @notice Deploys the AutoCompounding Vault.
    /// @param _asset The wMTN token (ERC20) used as the vault's underlying asset.
    /// @param _depositContract Address of the deposit contract that manages rewards.
    constructor(
        ERC20 _asset,
        address _depositContract
    ) ERC4626(_asset, "Auto Compounding MTN", "aMTN") {
        if (_depositContract == address(0)) revert DepositContractZero();
        depositContract = _depositContract;
    }

    // ========== VIEWS ==========

    // DF-10: Increase total assets backing aMTN as yield is harvested
    /// @notice Returns the total assets available in the vault (staked + earned streamed rewards).
    /// @dev Rewards are streamed linearly over REWARDS_DURATION.
    /// @return The total wMTN assets backing all aMTN shares.
    function totalAssets() public view override returns (uint256) {
        return totalStaked + earned();
    }

    /// @notice Returns the last time rewards are applicable.
    /// @dev Returns min(block.timestamp, periodFinish).
    /// @return The applicable timestamp for reward calculation.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Returns the amount of rewards per staked token.
    /// @dev Scaled by 1e18 for precision.
    /// @return The reward per token value.
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        }
        return
            (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalStaked;
    }

    /// @notice Returns earned rewards so far by the vault (not yet added to totalStaked).
    /// @dev Calculated as elapsed time * rewardRate since last update.
    /// @return The amount of rewards earned but not yet harvested.
    function earned() public view returns (uint256) {
        if (totalStaked == 0 || lastUpdateTime == 0) {
            return 0;
        }
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return elapsed * rewardRate;
    }

    // ========== EXTERNAL FUNCTIONS ==========

    // DF-4: Restrict certain functions to only be callable by the deposit contract
    /// @notice Notify the vault of new reward amount. Only callable by deposit contract.
    /// @dev Calculates new reward by subtracting totalStaked and earned() from balance.
    ///      Sets rewardRate based on REWARDS_DURATION. Updates timestamps.
    ///      Emits RewardAdded event.
    function notifyRewardAmount() external onlyDepositContract nonReentrant {
        // Calculate new reward amount:
        // total balance - currently staked - already earned rewards
        uint256 balance = asset.balanceOf(address(this));
        uint256 earnedSoFar = earned();
        uint256 newReward = balance - totalStaked - earnedSoFar;

        if (newReward == 0) revert NoNewRewards();

        // Update totalStaked to include previously earned rewards
        totalStaked += earnedSoFar;

        // Set new reward rate
        if (block.timestamp >= periodFinish) {
            rewardRate = newReward / REWARDS_DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (newReward + leftover) / REWARDS_DURATION;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + REWARDS_DURATION;

        emit RewardAdded(newReward);
    }

    // DF-9: Periodically harvest yield generated from underlying assets
    /// @notice Harvest: claim and stake available rewards into totalStaked.
    /// @dev Moves earned rewards into totalStaked, increasing share value for all holders.
    function harvest() external nonReentrant {
        uint256 earnedRewards = earned();
        if (earnedRewards > 0) {
            totalStaked += earnedRewards;
            lastUpdateTime = lastTimeRewardApplicable();
            emit Harvested(earnedRewards);
        }
    }

    // ========== DEPOSIT / MINT (inflation-protected) ==========

    // DF-7: Accept deposits of wMTN and mint proportional aMTN shares
    /// @notice Deposit wMTN assets and mint aMTN shares to the receiver.
    /// @dev Overrides ERC-4626 to lock MINIMUM_LIQUIDITY dead shares on the first deposit.
    /// @param assets Amount of wMTN to deposit.
    /// @param receiver Address to receive the minted aMTN shares.
    /// @return shares The amount of aMTN shares minted.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        shares = super.deposit(assets, receiver);
        _seedDeadShares(receiver, shares);
    }

    /// @notice Mint an exact number of aMTN shares to the receiver for wMTN assets.
    /// @dev Overrides ERC-4626 to lock MINIMUM_LIQUIDITY dead shares on the first mint.
    /// @param shares Amount of aMTN shares to mint.
    /// @param receiver Address to receive the minted aMTN shares.
    /// @return assets The amount of wMTN pulled in.
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();
        assets = super.mint(shares, receiver);
        _seedDeadShares(receiver, shares);
    }

    // DF-11: Allow withdrawals of aMTN for underlying wMTN
    /// @notice Withdraw an exact amount of wMTN assets by burning the owner's aMTN shares.
    /// @dev Overrides ERC-4626 to add a reentrancy guard and a zero-assets check.
    /// @param assets Amount of wMTN to withdraw.
    /// @param receiver Address to receive the withdrawn wMTN.
    /// @param owner Address whose aMTN shares are burned.
    /// @return shares The amount of aMTN shares burned.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAssets();
        shares = super.withdraw(assets, receiver, owner);
    }

    /// @notice Redeem aMTN shares for the underlying wMTN assets.
    /// @dev Overrides ERC-4626 to add a reentrancy guard and a zero-shares check.
    /// @param shares Amount of aMTN shares to redeem.
    /// @param receiver Address to receive the withdrawn wMTN.
    /// @param owner Address whose aMTN shares are burned.
    /// @return assets The amount of wMTN withdrawn.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroShares();
        assets = super.redeem(shares, receiver, owner);
    }

    /// @notice Locks MINIMUM_LIQUIDITY shares at DEAD_ADDRESS on the very first deposit/mint.
    /// @dev Requires the first deposit to mint strictly more than MINIMUM_LIQUIDITY shares,
    ///      then moves MINIMUM_LIQUIDITY of them to the dead address so they are never redeemable.
    /// @param receiver The first depositor whose shares back the locked minimum liquidity.
    /// @param mintedShares The shares just minted to `receiver`.
    function _seedDeadShares(address receiver, uint256 mintedShares) internal {
        if (!_deadSharesSeeded) {
            _deadSharesSeeded = true;
            if (mintedShares <= MINIMUM_LIQUIDITY) revert InitialDepositBelowMinimum();
            _burn(receiver, MINIMUM_LIQUIDITY);
            _mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
            emit DeadSharesSeeded(MINIMUM_LIQUIDITY);
        }
    }

    // ========== INTERNAL HOOKS ==========

    /// @notice Internal stake tracking on deposit/mint. Increments totalStaked.
    /// @param amount The amount of assets being staked.
    function _stake(uint256 amount) internal {
        totalStaked += amount;
    }

    /// @notice Internal withdraw tracking on withdraw/redeem. Decrements totalStaked.
    /// @param amount The amount of assets being withdrawn.
    function _withdrawInternal(uint256 amount) internal {
        totalStaked -= amount;
    }

    // DF-7: Accept deposits of wMTN and mint proportional aMTN shares
    /// @notice Hook called after deposit. Folds pending rewards in, then tracks staked amount.
    /// @dev Harvests any streamed-but-unbooked rewards into totalStaked before adding the new
    ///      deposit, so a fresh deposit cannot dilute existing holders' pending rewards.
    /// @param assets The amount of wMTN deposited.
    function afterDeposit(uint256 assets, uint256 /*shares*/) internal override {
        // Harvest any pending rewards first so they accrue to existing holders only.
        uint256 earnedRewards = earned();
        if (earnedRewards > 0) {
            totalStaked += earnedRewards;
        }
        lastUpdateTime = lastTimeRewardApplicable();
        _stake(assets);
    }

    // DF-11: Allow withdrawals of aMTN for underlying wMTN
    /// @notice Hook called before withdraw. Claims pending rewards and tracks withdrawn amount.
    /// @dev Inherited from ERC4626. Harvests earned rewards before decrementing totalStaked,
    ///      and always advances lastUpdateTime so reward accounting stays consistent.
    /// @param assets The amount of wMTN being withdrawn.
    function beforeWithdraw(uint256 assets, uint256 /*shares*/) internal override {
        // Claim any pending rewards into totalStaked before withdrawal
        uint256 earnedRewards = earned();
        if (earnedRewards > 0) {
            totalStaked += earnedRewards;
        }
        // Always update lastUpdateTime, even when there were no pending rewards.
        lastUpdateTime = lastTimeRewardApplicable();
        _withdrawInternal(assets);
    }
}
