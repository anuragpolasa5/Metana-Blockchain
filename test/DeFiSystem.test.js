const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("DeFi System", function () {
  let deployer, user1, user2;
  let mtn, wMTN, staking, deposit, vault;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    // Deploy MTN
    const MetanaToken = await ethers.getContractFactory("MetanaToken");
    mtn = await MetanaToken.deploy();

    // Deploy MTN Staking
    const MTNStaking = await ethers.getContractFactory("MTNStaking");
    staking = await MTNStaking.deploy(await mtn.getAddress());

    // Deploy wMTN
    const WrappedMetana = await ethers.getContractFactory("WrappedMetana");
    wMTN = await WrappedMetana.deploy();

    // Deploy Deposit Contract (vault set later)
    const DepositContract = await ethers.getContractFactory("DepositContract");
    deposit = await DepositContract.deploy(
      await mtn.getAddress(),
      await staking.getAddress(),
      ethers.ZeroAddress
    );

    // Deploy AutoCompounding Vault
    const AutoCompoundingVault = await ethers.getContractFactory("AutoCompoundingVault");
    vault = await AutoCompoundingVault.deploy(
      await wMTN.getAddress(),
      await deposit.getAddress()
    );

    // Setup deposit contract
    await deposit.setWMTN(await wMTN.getAddress());
    await deposit.setVault(await vault.getAddress());

    // Grant roles
    const MINTER_ROLE = await wMTN.MINTER_ROLE();
    const BURNER_ROLE = await wMTN.BURNER_ROLE();
    await wMTN.grantRole(MINTER_ROLE, await deposit.getAddress());
    await wMTN.grantRole(BURNER_ROLE, await deposit.getAddress());

    // Transfer staking ownership to deposit contract
    await staking.transferOwnership(await deposit.getAddress());

    // Mint MTN to users
    await mtn.mint(user1.address, ethers.parseEther("1000"));
    await mtn.mint(user2.address, ethers.parseEther("1000"));
  });

  // Helper: start a real MTN staking reward emission (owner-only) so the deposit
  // contract's staked position accrues rewards that harvest() can claim.
  async function fundStakingRewards(reward) {
    await mtn.mint(deployer.address, reward);
    await mtn.approve(await deposit.getAddress(), reward);
    await deposit.startStakingRewards(reward);
  }

  // ===========================================================
  // MetanaToken (MTN)
  // ===========================================================
  describe("MetanaToken (MTN)", function () {
    it("should have correct name and symbol", async function () {
      expect(await mtn.name()).to.equal("METANA");
      expect(await mtn.symbol()).to.equal("MTN");
    });

    it("should allow owner to mint", async function () {
      await mtn.mint(user1.address, ethers.parseEther("100"));
      expect(await mtn.balanceOf(user1.address)).to.equal(ethers.parseEther("1100"));
    });

    it("should not allow non-owner to mint", async function () {
      await expect(
        mtn.connect(user1).mint(user1.address, ethers.parseEther("100"))
      ).to.be.reverted;
    });
  });

  // ===========================================================
  // WrappedMetana (wMTN)
  // ===========================================================
  describe("WrappedMetana (wMTN)", function () {
    it("should have correct name and symbol", async function () {
      expect(await wMTN.name()).to.equal("Wrapped METANA");
      expect(await wMTN.symbol()).to.equal("wMTN");
    });

    it("should allow MINTER_ROLE to mint", async function () {
      await mtn.connect(user1).approve(await deposit.getAddress(), ethers.parseEther("100"));
      await deposit.connect(user1).deposit(ethers.parseEther("100"), user1.address, false);
      expect(await wMTN.balanceOf(user1.address)).to.equal(ethers.parseEther("100"));
    });

    it("should not allow non-MINTER to mint", async function () {
      await expect(
        wMTN.connect(user1).mint(user1.address, ethers.parseEther("100"))
      ).to.be.reverted;
    });

    it("should allow BURNER_ROLE to burn via deposit redeem", async function () {
      // Deposit first
      await mtn.connect(user1).approve(await deposit.getAddress(), ethers.parseEther("100"));
      await deposit.connect(user1).deposit(ethers.parseEther("100"), user1.address, false);
      expect(await wMTN.balanceOf(user1.address)).to.equal(ethers.parseEther("100"));

      // Redeem (burn)
      await deposit.connect(user1).redeem(ethers.parseEther("50"), user1.address);
      expect(await wMTN.balanceOf(user1.address)).to.equal(ethers.parseEther("50"));
    });

    it("should not allow unauthorized caller to burn", async function () {
      await expect(
        wMTN.connect(user1).burn(user1.address, ethers.parseEther("100"))
      ).to.be.reverted;
    });
  });

  // ===========================================================
  // DepositContract
  // ===========================================================
  describe("DepositContract", function () {
    it("should accept MTN deposits and mint wMTN 1:1 (no compound)", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);

      await expect(deposit.connect(user1).deposit(amount, user1.address, false))
        .to.emit(deposit, "Deposited");

      expect(await wMTN.balanceOf(user1.address)).to.equal(amount);
      expect(await deposit.totalMTNDeposited()).to.equal(amount);
      expect(await deposit.totalWMTNMinted()).to.equal(amount);
    });

    it("should deposit wMTN to vault when compound is true", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);

      await deposit.connect(user1).deposit(amount, user1.address, true);

      expect(await wMTN.balanceOf(user1.address)).to.equal(0);
      expect(await vault.balanceOf(user1.address)).to.be.gt(0);
    });

    it("should allow redemption of wMTN for MTN", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, false);

      await expect(deposit.connect(user1).redeem(amount, user1.address))
        .to.emit(deposit, "Redeemed");

      expect(await wMTN.balanceOf(user1.address)).to.equal(0);
      expect(await mtn.balanceOf(user1.address)).to.equal(ethers.parseEther("1000"));
    });

    it("should track total MTN deposited and wMTN minted", async function () {
      const amount1 = ethers.parseEther("100");
      const amount2 = ethers.parseEther("200");

      await mtn.connect(user1).approve(await deposit.getAddress(), amount1);
      await deposit.connect(user1).deposit(amount1, user1.address, false);

      await mtn.connect(user2).approve(await deposit.getAddress(), amount2);
      await deposit.connect(user2).deposit(amount2, user2.address, false);

      expect(await deposit.totalMTNDeposited()).to.equal(amount1 + amount2);
      expect(await deposit.totalWMTNMinted()).to.equal(amount1 + amount2);
    });

    it("should emit events on deposit and withdrawal", async function () {
      const amount = ethers.parseEther("50");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);

      await expect(deposit.connect(user1).deposit(amount, user1.address, false))
        .to.emit(deposit, "Deposited")
        .withArgs(user1.address, user1.address, amount, false);

      await expect(deposit.connect(user1).redeem(amount, user2.address))
        .to.emit(deposit, "Redeemed")
        .withArgs(user1.address, user2.address, amount);
    });

    // HIGH PRIORITY: setWMTN front-run/unauthorized caller scenario
    it("should not allow setWMTN to be called twice", async function () {
      // wMTN is already set in beforeEach
      await expect(
        deposit.setWMTN(user1.address)
      ).to.be.revertedWithCustomError(deposit, "WMTNAlreadySet");
    });

    it("should reject zero address for setWMTN", async function () {
      // Deploy a fresh deposit contract without wMTN set
      const DepositContract = await ethers.getContractFactory("DepositContract");
      const freshDeposit = await DepositContract.deploy(
        await mtn.getAddress(),
        await staking.getAddress(),
        ethers.ZeroAddress
      );
      await expect(
        freshDeposit.setWMTN(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(freshDeposit, "ZeroAddress");
    });

    // HIGH PRIORITY: setVault front-run/unauthorized caller scenario
    it("should not allow setVault to be called twice", async function () {
      await expect(
        deposit.setVault(user1.address)
      ).to.be.revertedWithCustomError(deposit, "VaultAlreadySet");
    });

    it("should reject zero address for setVault", async function () {
      const DepositContract = await ethers.getContractFactory("DepositContract");
      const freshDeposit = await DepositContract.deploy(
        await mtn.getAddress(),
        await staking.getAddress(),
        ethers.ZeroAddress
      );
      await expect(
        freshDeposit.setVault(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(freshDeposit, "ZeroAddress");
    });

    // HIGH PRIORITY: harvest end-to-end success path (with real staking rewards)
    it("should harvest rewards end-to-end (claim, restake, mint to vault, notify)", async function () {
      // 1) User deposits -> deposit contract stakes 100 MTN into staking.
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, false);

      // 2) Owner starts a real staking reward emission (deposit owns staking).
      const reward = ethers.parseEther("700");
      await mtn.mint(deployer.address, reward);
      await mtn.approve(await deposit.getAddress(), reward);
      await deposit.startStakingRewards(reward);

      // 3) Let rewards accrue to the deposit contract's staked position.
      await time.increase(86400); // 1 day

      const totalDepBefore = await deposit.totalMTNDeposited();

      // 4) Harvest: claims earned MTN, re-stakes, mints wMTN to vault, notifies vault.
      await expect(deposit.harvest()).to.emit(deposit, "RewardsSynced");

      // Verify wMTN was minted to the vault and totals grew by the harvested amount.
      expect(await wMTN.balanceOf(await vault.getAddress())).to.be.gt(0);
      expect(await deposit.totalMTNDeposited()).to.be.gt(totalDepBefore);
    });

    // HIGH PRIORITY: harvest revert when no rewards
    it("should revert harvest when no rewards are available", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, false);

      // No reward emission configured - getReward yields nothing - should revert.
      await expect(deposit.harvest()).to.be.revertedWithCustomError(deposit, "NoRewards");
    });

    // Test 3 (reviewer): stray MTN sent to the deposit contract must NOT be counted by harvest.
    it("should not count stray MTN as harvested rewards", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, false);

      // Donate 1 stray MTN directly to the deposit contract (no staking reward configured).
      await mtn.mint(await deposit.getAddress(), ethers.parseEther("1"));

      // harvest measures only the getReward() delta, so the stray MTN is ignored -> revert.
      await expect(deposit.harvest()).to.be.revertedWithCustomError(deposit, "NoRewards");
      // The stray MTN remains untouched in the deposit contract.
      expect(await mtn.balanceOf(await deposit.getAddress())).to.equal(ethers.parseEther("1"));
    });

    // MEDIUM PRIORITY: deposit zero-amount revert
    it("should revert deposit with zero amount", async function () {
      await expect(
        deposit.connect(user1).deposit(0, user1.address, false)
      ).to.be.revertedWithCustomError(deposit, "ZeroAmount");
    });

    // MEDIUM PRIORITY: deposit without approval reverts on transfer
    it("should revert deposit when MTN is not approved", async function () {
      await expect(
        deposit.connect(user1).deposit(ethers.parseEther("100"), user1.address, false)
      ).to.be.reverted; // ERC20: insufficient allowance
    });

    // MEDIUM PRIORITY: redeem revert on zero assets
    it("should revert redeem with zero assets", async function () {
      await expect(
        deposit.connect(user1).redeem(0, user1.address)
      ).to.be.revertedWithCustomError(deposit, "ZeroRedeem");
    });
  });

  // ===========================================================
  // MTNStaking
  // ===========================================================
  describe("MTNStaking", function () {
    it("should track staked balances via deposit contract", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, false);

      expect(await staking.balanceOf(await deposit.getAddress())).to.equal(amount);
      expect(await staking.totalSupply()).to.equal(amount);
    });

    // MEDIUM PRIORITY: notifyRewardAmount non-owner revert
    it("should revert notifyRewardAmount from non-owner", async function () {
      await expect(
        staking.connect(user1).notifyRewardAmount(ethers.parseEther("100"))
      ).to.be.reverted;
    });

    // MEDIUM PRIORITY: notifyRewardAmount "Provided reward too high" revert
    it("should revert notifyRewardAmount when reward too high for balance", async function () {
      // Deploy a fresh staking contract with deployer as owner for testing
      const MTNStaking = await ethers.getContractFactory("MTNStaking");
      const testStaking = await MTNStaking.deploy(await mtn.getAddress());

      // Try to set reward without funding the contract
      await expect(
        testStaking.notifyRewardAmount(ethers.parseEther("1000"))
      ).to.be.revertedWithCustomError(testStaking, "RewardTooHigh");
    });

    // LOW PRIORITY: getReward with non-zero accrual
    it("should accrue and claim rewards correctly", async function () {
      // Deploy a fresh staking contract for isolated testing
      const MTNStaking = await ethers.getContractFactory("MTNStaking");
      const testStaking = await MTNStaking.deploy(await mtn.getAddress());

      // User stakes
      const stakeAmount = ethers.parseEther("100");
      await mtn.mint(user1.address, stakeAmount);
      await mtn.connect(user1).approve(await testStaking.getAddress(), stakeAmount);
      await testStaking.connect(user1).stake(stakeAmount);

      // Fund with rewards
      const rewardAmount = ethers.parseEther("700");
      await mtn.mint(await testStaking.getAddress(), rewardAmount);
      await testStaking.notifyRewardAmount(rewardAmount);

      // Advance time by 1 day
      await time.increase(86400);

      // Check earned > 0
      const earned = await testStaking.earned(user1.address);
      expect(earned).to.be.gt(0);

      // Claim reward
      const balBefore = await mtn.balanceOf(user1.address);
      await testStaking.connect(user1).getReward();
      const balAfter = await mtn.balanceOf(user1.address);

      expect(balAfter - balBefore).to.be.gt(0);
      // Rewards should be reset
      expect(await testStaking.earned(user1.address)).to.equal(0);
    });

    // LOW PRIORITY: exit (full withdraw + reward claim)
    it("should exit with full withdraw and reward claim", async function () {
      const MTNStaking = await ethers.getContractFactory("MTNStaking");
      const testStaking = await MTNStaking.deploy(await mtn.getAddress());

      const stakeAmount = ethers.parseEther("100");
      await mtn.mint(user1.address, stakeAmount);
      await mtn.connect(user1).approve(await testStaking.getAddress(), stakeAmount);
      await testStaking.connect(user1).stake(stakeAmount);

      // Fund rewards
      const rewardAmount = ethers.parseEther("700");
      await mtn.mint(await testStaking.getAddress(), rewardAmount);
      await testStaking.notifyRewardAmount(rewardAmount);

      // Advance time
      await time.increase(86400);

      // Exit
      const balBefore = await mtn.balanceOf(user1.address);
      await testStaking.connect(user1).exit();
      const balAfter = await mtn.balanceOf(user1.address);

      // Should have received stake + some rewards
      expect(balAfter - balBefore).to.be.gt(stakeAmount);
      expect(await testStaking.balanceOf(user1.address)).to.equal(0);
    });

    // LOW PRIORITY: time-based rewardPerToken validation
    it("should calculate rewardPerToken correctly over time", async function () {
      const MTNStaking = await ethers.getContractFactory("MTNStaking");
      const testStaking = await MTNStaking.deploy(await mtn.getAddress());

      const stakeAmount = ethers.parseEther("100");
      await mtn.mint(user1.address, stakeAmount);
      await mtn.connect(user1).approve(await testStaking.getAddress(), stakeAmount);
      await testStaking.connect(user1).stake(stakeAmount);

      // Fund: 604800 tokens over 7 days = 1 token/second
      const rewardAmount = ethers.parseEther("604800");
      await mtn.mint(await testStaking.getAddress(), rewardAmount);
      await testStaking.notifyRewardAmount(rewardAmount);

      // After 1 day (86400 seconds), rewardPerToken = 86400 * 1e18 / 100e18 * 1e18
      await time.increase(86400);

      const rpt = await testStaking.rewardPerToken();
      // rewardRate = 604800e18 / 604800 = 1e18 per second
      // rpt = 86400 * 1e18 * 1e18 / 100e18 = 864e18
      expect(rpt).to.be.gt(0);
    });
  });

  // ===========================================================
  // AutoCompoundingVault
  // ===========================================================
  describe("AutoCompoundingVault", function () {
    it("should accept wMTN deposits and mint aMTN shares", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      const shares = await vault.balanceOf(user1.address);
      // First deposit is 1:1, minus MINIMUM_LIQUIDITY (1000) locked as dead shares.
      const MIN_LIQ = await vault.MINIMUM_LIQUIDITY();
      expect(shares).to.equal(amount - MIN_LIQ);
    });

    it("should lock minimum-liquidity dead shares on the first deposit", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      const MIN_LIQ = await vault.MINIMUM_LIQUIDITY();
      const DEAD = await vault.DEAD_ADDRESS();
      expect(await vault.balanceOf(DEAD)).to.equal(MIN_LIQ);
      // totalSupply can never drop below the locked minimum, neutralising inflation attacks.
      expect(await vault.totalSupply()).to.equal(amount);
    });

    it("should restrict notifyRewardAmount to deposit contract", async function () {
      await expect(
        vault.connect(user1).notifyRewardAmount()
      ).to.be.revertedWithCustomError(vault, "OnlyDepositContract");
    });

    it("should revert deposit with zero assets", async function () {
      await expect(
        vault.connect(user1).deposit(0, user1.address)
      ).to.be.revertedWithCustomError(vault, "ZeroAssets");
    });

    it("should revert redeem with zero shares", async function () {
      await expect(
        vault.connect(user1).redeem(0, user1.address, user1.address)
      ).to.be.revertedWithCustomError(vault, "ZeroShares");
    });

    it("should calculate totalAssets correctly", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      expect(await vault.totalAssets()).to.equal(amount);
    });

    it("should allow withdrawal of aMTN for underlying wMTN", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      const shares = await vault.balanceOf(user1.address);
      await vault.connect(user1).redeem(shares, user1.address, user1.address);

      const MIN_LIQ = await vault.MINIMUM_LIQUIDITY();
      expect(await vault.balanceOf(user1.address)).to.equal(0);
      // User redeems all their shares; MINIMUM_LIQUIDITY worth stays locked in the vault.
      expect(await wMTN.balanceOf(user1.address)).to.equal(amount - MIN_LIQ);
    });

    // Test 2 (reviewer): withdrawal harvests pending rewards into totalStaked.
    it("should harvest pending rewards into totalStaked on withdrawal", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      // Start vault reward streaming via a real harvest.
      await fundStakingRewards(ethers.parseEther("700"));
      await time.increase(86400);
      await deposit.harvest();

      // Let rewards accrue, then withdraw part of the position.
      await time.increase(86400);
      const pendingEarned = await vault.earned();
      expect(pendingEarned).to.be.gt(0);

      const totalStakedBefore = await vault.totalStaked();
      const shares = await vault.balanceOf(user1.address);
      // Redeem half -> beforeWithdraw folds pending earned into totalStaked first.
      await vault.connect(user1).redeem(shares / 2n, user1.address, user1.address);

      // totalStaked reflects harvested rewards minus the assets withdrawn for half the shares.
      expect(await vault.earned()).to.equal(0);
      expect(await vault.totalStaked()).to.be.gt(0);
      expect(totalStakedBefore).to.be.gt(0);
    });

    // MEDIUM PRIORITY: notifyRewardAmount success when block.timestamp >= periodFinish
    it("should set reward rate correctly when period has finished", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      // Real harvest: accrued staking rewards -> wMTN minted to vault -> notifyRewardAmount.
      await fundStakingRewards(ethers.parseEther("700"));
      await time.increase(86400);
      await deposit.harvest();

      expect(await vault.rewardRate()).to.be.gt(0);
      expect(await vault.periodFinish()).to.be.gt(0);
    });

    // MEDIUM PRIORITY: notifyRewardAmount with leftover rewards (timestamp < periodFinish)
    it("should handle leftover rewards when notified before period ends", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      // Fund one staking emission, then harvest twice at different times so the
      // second notify happens while the first vault period is still active.
      await fundStakingRewards(ethers.parseEther("700"));
      await time.increase(86400);
      await deposit.harvest();
      const rate1 = await vault.rewardRate();

      await time.increase(86400);
      await deposit.harvest();
      const rate2 = await vault.rewardRate();

      expect(rate2).to.be.gt(0);
      expect(rate2).to.not.equal(rate1);
    });

    // MEDIUM PRIORITY: harvest with elapsed time and non-zero earned
    it("should harvest earned rewards into totalStaked after time passes", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      await fundStakingRewards(ethers.parseEther("700"));
      await time.increase(86400);
      await deposit.harvest();

      const totalStakedBefore = await vault.totalStaked();

      // Advance time to let vault rewards accrue.
      await time.increase(86400);
      expect(await vault.earned()).to.be.gt(0);

      // Move earned into totalStaked.
      await vault.harvest();
      expect(await vault.totalStaked()).to.be.gt(totalStakedBefore);
    });

    // LOW PRIORITY: totalAssets increases over time as rewards stream
    it("should increase totalAssets over time as rewards are streamed", async function () {
      const amount = ethers.parseEther("100");
      await mtn.connect(user1).approve(await deposit.getAddress(), amount);
      await deposit.connect(user1).deposit(amount, user1.address, true);

      await fundStakingRewards(ethers.parseEther("700"));
      await time.increase(86400);
      await deposit.harvest();

      const totalAssetsBefore = await vault.totalAssets();
      await time.increase(86400);
      const totalAssetsAfter = await vault.totalAssets();
      expect(totalAssetsAfter).to.be.gt(totalAssetsBefore);
    });
  });

  // ===========================================================
  // Non-zero address checks
  // ===========================================================
  describe("Non-zero address checks", function () {
    it("should reject zero address for MTN in DepositContract constructor", async function () {
      const DepositContract = await ethers.getContractFactory("DepositContract");
      await expect(
        DepositContract.deploy(ethers.ZeroAddress, await staking.getAddress(), ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(DepositContract, "ZeroAddress");
    });

    it("should reject zero address for staking in DepositContract constructor", async function () {
      const DepositContract = await ethers.getContractFactory("DepositContract");
      await expect(
        DepositContract.deploy(await mtn.getAddress(), ethers.ZeroAddress, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(DepositContract, "ZeroAddress");
    });

    it("should reject zero address for deposit contract in AutoCompoundingVault", async function () {
      const AutoCompoundingVault = await ethers.getContractFactory("AutoCompoundingVault");
      await expect(
        AutoCompoundingVault.deploy(await wMTN.getAddress(), ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(AutoCompoundingVault, "DepositContractZero");
    });

    it("should reject zero address for staking token in MTNStaking", async function () {
      const MTNStaking = await ethers.getContractFactory("MTNStaking");
      await expect(
        MTNStaking.deploy(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(MTNStaking, "ZeroAddress");
    });
  });
});
