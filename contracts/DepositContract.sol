// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWrappedMetana {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMTNStaking {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function earned(address account) external view returns (uint256);
    function notifyRewardAmount(uint256 reward) external;
}

interface IAutoCompoundingVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function notifyRewardAmount() external;
}

/// @title DepositContract
/// @author Anurag
/// @notice Core deposit contract for the DeFi system.
///         Accepts MTN deposits, mints wMTN 1:1, stakes into MTNStaking,
///         supports autocompounding via ERC-4626 vault, and harvests rewards.
/// @dev Constructor takes underlying token (MTN), staking contract address, and vault address.
///      Acts as the central coordinator between MTN, wMTN, staking, and autocompounding vault.
contract DepositContract is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== CUSTOM ERRORS ==========

    /// @dev Thrown when a required address argument is the zero address.
    error ZeroAddress();
    /// @dev Thrown when wMTN has already been set.
    error WMTNAlreadySet();
    /// @dev Thrown when the vault has already been set.
    error VaultAlreadySet();
    /// @dev Thrown when a deposit amount is zero.
    error ZeroAmount();
    /// @dev Thrown when a redeem amount is zero.
    error ZeroRedeem();
    /// @dev Thrown when harvest finds no claimed rewards to sync.
    error NoRewards();

    // ========== STATE VARIABLES ==========

    /// @notice The underlying MTN token. Wired immutably at construction.
    IERC20 public immutable mtn;

    /// @notice The wrapped MTN (wMTN) token with mint/burn access.
    IWrappedMetana public wMTN;

    /// @notice The MTN staking contract for earning rewards. Wired immutably at construction.
    IMTNStaking public immutable stakingContract;

    /// @notice The autocompounding ERC-4626 vault for wMTN.
    IAutoCompoundingVault public autoCompoundingVault;

    // DF-5: Track total MTN deposited and wMTN minted
    /// @notice Total amount of MTN deposited into the system.
    uint256 public totalMTNDeposited;

    /// @notice Total amount of wMTN minted by the system.
    uint256 public totalWMTNMinted;

    // ========== EVENTS ==========

    // DF-6: Emit events on deposit, withdrawal, and reward sync
    /// @notice Emitted when a user deposits MTN.
    /// @param user The depositor address.
    /// @param receiver The address receiving wMTN or aMTN.
    /// @param amount The amount of MTN deposited.
    /// @param compound Whether the deposit was autocompounded.
    event Deposited(address indexed user, address indexed receiver, uint256 amount, bool compound);

    /// @notice Emitted when a user redeems wMTN for MTN.
    /// @param user The redeemer address.
    /// @param receiver The address receiving MTN.
    /// @param amount The amount of wMTN redeemed.
    event Redeemed(address indexed user, address indexed receiver, uint256 amount);

    /// @notice Emitted when rewards are harvested and synced to the vault.
    /// @param rewardAmount The amount of MTN rewards harvested.
    event RewardsSynced(uint256 rewardAmount);

    // ========== CONSTRUCTOR ==========

    /// @notice Deploys the DepositContract.
    /// @dev Vault address can be zero initially and set later via setVault().
    /// @param _mtn Address of the underlying MTN token.
    /// @param _stakingContract Address of the MTN staking contract.
    /// @param _autoCompoundingVault Address of the autocompounding vault (or zero address).
    constructor(
        address _mtn,
        address _stakingContract,
        address _autoCompoundingVault
    ) Ownable(msg.sender) {
        if (_mtn == address(0)) revert ZeroAddress();
        if (_stakingContract == address(0)) revert ZeroAddress();
        mtn = IERC20(_mtn);
        stakingContract = IMTNStaking(_stakingContract);
        if (_autoCompoundingVault != address(0)) {
            autoCompoundingVault = IAutoCompoundingVault(_autoCompoundingVault);
        }
    }

    /// @notice Set the wMTN token address. Owner-only, can only be called once.
    /// @dev Two-phase wiring is retained (rather than a constructor arg) so the wMTN
    ///      token can grant MINTER/BURNER roles to this contract before it goes live.
    ///      Guarded by `onlyOwner` plus a one-time + non-zero check to block front-running.
    /// @param _wMTN Address of the WrappedMetana token.
    function setWMTN(address _wMTN) external onlyOwner {
        if (address(wMTN) != address(0)) revert WMTNAlreadySet();
        if (_wMTN == address(0)) revert ZeroAddress();
        wMTN = IWrappedMetana(_wMTN);
    }

    /// @notice Set the autocompounding vault address. Owner-only, can only be called once.
    /// @dev A mutable setter is required here because of the circular dependency: the vault
    ///      constructor needs this contract's address, so the vault cannot exist when this
    ///      contract is constructed. Guarded by `onlyOwner` plus one-time + non-zero checks.
    /// @param _vault Address of the AutoCompoundingVault.
    function setVault(address _vault) external onlyOwner {
        if (address(autoCompoundingVault) != address(0)) revert VaultAlreadySet();
        if (_vault == address(0)) revert ZeroAddress();
        autoCompoundingVault = IAutoCompoundingVault(_vault);
    }

    // ========== EXTERNAL FUNCTIONS ==========

    // DF-1: Accept deposits of MTN tokens and mint wMTN at 1:1 ratio
    /// @notice Deposit a specific amount of MTN tokens. Stakes MTN and mints wMTN 1:1.
    /// @dev User must approve this contract for at least `_amount` MTN before calling.
    ///      The approval acts as a spending cap; exactly `_amount` is pulled in.
    ///      If _compound is false, wMTN is minted to _receiver.
    ///      If _compound is true, wMTN is deposited into the vault and _receiver gets aMTN.
    /// @param _amount The exact amount of MTN to deposit. Must be greater than zero.
    /// @param _receiver Address to receive wMTN (or aMTN if compounding).
    /// @param _compound If true, deposits wMTN into autocompounding vault for aMTN.
    function deposit(uint256 _amount, address _receiver, bool _compound) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();

        // Pull exactly `_amount` from the caller (approval is a cap, not the transfer amount).
        mtn.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amount = _amount;

        // Stake MTN into staking contract
        mtn.approve(address(stakingContract), amount);
        stakingContract.stake(amount);

        // DF-5: Track total MTN deposited and wMTN minted
        totalMTNDeposited += amount;
        totalWMTNMinted += amount;

        if (_compound) {
            // Mint wMTN to this contract, then deposit into vault for _receiver
            wMTN.mint(address(this), amount);
            wMTN.approve(address(autoCompoundingVault), amount);
            // DF-3: Notify the ERC-4626 vault of deposited assets
            autoCompoundingVault.deposit(amount, _receiver);
        } else {
            // Mint wMTN directly to _receiver
            wMTN.mint(_receiver, amount);
        }

        // DF-6: Emit events on deposit
        emit Deposited(msg.sender, _receiver, amount, _compound);
    }

    /// @notice Redeem wMTN for underlying MTN.
    /// @dev Burns wMTN from caller, withdraws MTN from staking, transfers to _receiver.
    /// @param _assets Amount of wMTN to redeem.
    /// @param _receiver Address to receive the underlying MTN.
    function redeem(uint256 _assets, address _receiver) external nonReentrant {
        if (_assets == 0) revert ZeroRedeem();
        if (_receiver == address(0)) revert ZeroAddress();

        // Withdraw MTN from staking contract
        stakingContract.withdraw(_assets);

        // Burn wMTN from the caller
        wMTN.burn(msg.sender, _assets);

        // Transfer MTN to receiver
        mtn.safeTransfer(_receiver, _assets);

        // DF-5: Track total MTN deposited and wMTN minted
        totalMTNDeposited -= _assets;
        totalWMTNMinted -= _assets;

        // DF-6: Emit events on withdrawal
        emit Redeemed(msg.sender, _receiver, _assets);
    }

    // DF-2: Sync newly added rewards for streaming over time
    /// @notice Harvest rewards from staking contract, re-stake, mint wMTN to vault, and notify.
    /// @dev Claims MTN rewards from staking, re-stakes them, mints equivalent wMTN to vault,
    ///      and calls notifyRewardAmount() on the vault to stream rewards over time.
    function harvest() external nonReentrant {
        // Snapshot balance before claiming so we only count *claimed* rewards and
        // ignore any stray/donated MTN sitting in this contract.
        uint256 balanceBefore = mtn.balanceOf(address(this));

        // Claim rewards from staking contract
        stakingContract.getReward();

        // Only the delta produced by getReward() counts as harvested reward.
        uint256 rewardAmount = mtn.balanceOf(address(this)) - balanceBefore;
        if (rewardAmount == 0) revert NoRewards();

        // Re-stake the rewards into staking contract
        mtn.approve(address(stakingContract), rewardAmount);
        stakingContract.stake(rewardAmount);

        // Mint wMTN to the autocompounding vault
        wMTN.mint(address(autoCompoundingVault), rewardAmount);

        // DF-3: Notify the ERC-4626 vault of deposited assets
        autoCompoundingVault.notifyRewardAmount();

        // DF-5: Track total MTN deposited and wMTN minted
        totalMTNDeposited += rewardAmount;
        totalWMTNMinted += rewardAmount;

        // DF-6: Emit events on reward sync
        emit RewardsSynced(rewardAmount);
    }

    /// @notice Start (or top up) the MTN staking reward emission. Owner-only.
    /// @dev This contract owns MTNStaking, so it is the only address allowed to call its
    ///      onlyOwner notifyRewardAmount. The reward tokens are funded into the staking
    ///      contract first so its internal `rewardRate <= balance / duration` check passes.
    ///      The caller must approve this contract for `reward` MTN beforehand.
    /// @param reward The amount of MTN to stream as staking rewards over the staking duration.
    function startStakingRewards(uint256 reward) external onlyOwner {
        if (reward == 0) revert ZeroAmount();
        // Fund the staking contract with the reward tokens, then start the emission.
        mtn.safeTransferFrom(msg.sender, address(stakingContract), reward);
        stakingContract.notifyRewardAmount(reward);
    }
}
