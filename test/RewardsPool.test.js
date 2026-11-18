const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseEther, ZeroAddress } = ethers;


describe("Role-Based Rewards Pool", function () {
  let communityToken, rewardsVault;
  let admin, treasurer, pauser, auditor, donor, stranger, foundation;

  before(async () => {
    [admin, treasurer, pauser, auditor, donor, stranger, foundation] =
      await ethers.getSigners();
  });

  beforeEach(async () => {
    // ── Deploy CommunityToken ──────────────────────────────────────────────
    const CommunityToken = await ethers.getContractFactory("CommunityToken");
    communityToken = await CommunityToken.deploy("CommunityToken", "CTK", admin.address);
    await communityToken.waitForDeployment();

    // ── Deploy RewardsVault ────────────────────────────────────────────────
    const RewardsVault = await ethers.getContractFactory("RewardsVault");
    rewardsVault = await RewardsVault.deploy(
      await communityToken.getAddress(),
      admin.address,
      foundation.address
    );
    await rewardsVault.waitForDeployment();

    // ── Grant MINTER_ROLE to vault ─────────────────────────────────────────
    const MINTER_ROLE = await communityToken.MINTER_ROLE();
    await communityToken.connect(admin).grantRole(MINTER_ROLE, await rewardsVault.getAddress());

    // ── Grant TREASURER_ROLE ───────────────────────────────────────────────
    const TREASURER_ROLE = await rewardsVault.TREASURER_ROLE();
    await rewardsVault.connect(admin).grantRole(TREASURER_ROLE, treasurer.address);

    // ── Grant PAUSER_ROLE to pauser & auditor (AUDITOR_ROLE == PAUSER_ROLE) ─
    const PAUSER_ROLE = await rewardsVault.PAUSER_ROLE();
    await rewardsVault.connect(admin).grantRole(PAUSER_ROLE, pauser.address);
    await rewardsVault.connect(admin).grantRole(PAUSER_ROLE, auditor.address);

    // ── Grant PAUSER_ROLE on token contract to pauser ─────────────────────
    const TOKEN_PAUSER_ROLE = await communityToken.PAUSER_ROLE();
    await communityToken.connect(admin).grantRole(TOKEN_PAUSER_ROLE, pauser.address);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Deployment & Role Setup
  // ═══════════════════════════════════════════════════════════════════════════
  describe("Deployment", () => {
    it("CT: admin holds DEFAULT_ADMIN_ROLE and PAUSER_ROLE", async () => {
      expect(await communityToken.hasRole(await communityToken.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
      expect(await communityToken.hasRole(await communityToken.PAUSER_ROLE(), admin.address)).to.be.true;
    });

    it("Vault: admin holds DEFAULT_ADMIN_ROLE and PAUSER_ROLE", async () => {
      expect(await rewardsVault.hasRole(await rewardsVault.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
      expect(await rewardsVault.hasRole(await rewardsVault.PAUSER_ROLE(), admin.address)).to.be.true;
    });

    it("Vault: AUDITOR_ROLE equals PAUSER_ROLE", async () => {
      expect(await rewardsVault.AUDITOR_ROLE()).to.equal(await rewardsVault.PAUSER_ROLE());
    });

    it("Vault: RATE is 0.01 ether (1 token per 0.01 ETH)", async () => {
      expect(await rewardsVault.RATE()).to.equal(parseEther("0.01"));
    });

    it("Vault: foundationWallet is set correctly", async () => {
      expect(await rewardsVault.foundationWallet()).to.equal(foundation.address);
    });

    it("Vault: constructor reverts on zero token address", async () => {
      const RewardsVault = await ethers.getContractFactory("RewardsVault");
      await expect(
        RewardsVault.deploy(ZeroAddress, admin.address, foundation.address)
      ).to.be.reverted;
    });

    it("Vault: constructor reverts on zero foundation wallet", async () => {
      const RewardsVault = await ethers.getContractFactory("RewardsVault");
      await expect(
        RewardsVault.deploy(await communityToken.getAddress(), admin.address, ZeroAddress)
      ).to.be.reverted;
    });

    it("Vault: constructor reverts on zero admin address", async () => {
      const RewardsVault = await ethers.getContractFactory("RewardsVault");
      await expect(
        RewardsVault.deploy(await communityToken.getAddress(), ZeroAddress, foundation.address)
      ).to.be.revertedWithCustomError(rewardsVault, "ZeroAddress");
    });

    it("CT: constructor reverts on zero admin address", async () => {
      const CommunityToken = await ethers.getContractFactory("CommunityToken");
      await expect(
        CommunityToken.deploy("CommunityToken", "CTK", ZeroAddress)
      ).to.be.revertedWith("CommunityToken: zero admin");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. donate() — Required Test 1
  // ═══════════════════════════════════════════════════════════════════════════
  describe("donate()", () => {
    it("[REQ-1] mints the correct token amount for 0.01 ETH", async () => {
      const donateAmount = parseEther("0.01");
      await expect(
        rewardsVault.connect(donor).donate({ value: donateAmount })
      ).to.changeTokenBalance(communityToken, donor, parseEther("1"));
    });

    it("[REQ-1] mints correct tokens for 0.05 ETH (5 tokens)", async () => {
      const donateAmount = parseEther("0.05");
      await expect(
        rewardsVault.connect(donor).donate({ value: donateAmount })
      ).to.changeTokenBalance(communityToken, donor, parseEther("5"));
    });

    it("[REQ-1] mints correct tokens for 1 ETH (100 tokens)", async () => {
      const donateAmount = parseEther("1");
      await expect(
        rewardsVault.connect(donor).donate({ value: donateAmount })
      ).to.changeTokenBalance(communityToken, donor, parseEther("100"));
    });

    it("[REQ-1] emits Donation event with correct args", async () => {
      const donateAmount = parseEther("0.1");
      await expect(
        rewardsVault.connect(donor).donate({ value: donateAmount })
      )
        .to.emit(rewardsVault, "Donation")
        .withArgs(donor.address, donateAmount, parseEther("10"));
    });

    it("ETH balance of vault increases after donation", async () => {
      const donateAmount = parseEther("0.5");
      await expect(
        rewardsVault.connect(donor).donate({ value: donateAmount })
      ).to.changeEtherBalance(rewardsVault, donateAmount);
    });

    it("reverts when msg.value is 0", async () => {
      await expect(
        rewardsVault.connect(donor).donate({ value: 0 })
      ).to.be.reverted;
    });

    it("multiple donors each receive correct tokens independently", async () => {
      const [d1, d2] = [donor, stranger];
      await rewardsVault.connect(d1).donate({ value: parseEther("0.02") });
      await rewardsVault.connect(d2).donate({ value: parseEther("0.03") });
      expect(await communityToken.balanceOf(d1.address)).to.equal(parseEther("2"));
      expect(await communityToken.balanceOf(d2.address)).to.equal(parseEther("3"));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. withdraw() — Required Test 2
  // ═══════════════════════════════════════════════════════════════════════════
  describe("withdraw()", () => {
    beforeEach(async () => {
      // Seed the vault with 1 ETH
      await rewardsVault.connect(donor).donate({ value: parseEther("1") });
    });

    it("[REQ-2] treasurer can withdraw ETH to foundation wallet", async () => {
      const withdrawAmount = parseEther("0.5");
      await expect(
        rewardsVault.connect(treasurer).withdraw(withdrawAmount)
      ).to.changeEtherBalance(foundation, withdrawAmount);
    });

    it("[REQ-2] emits Withdrawal event", async () => {
      const amount = parseEther("0.3");
      await expect(rewardsVault.connect(treasurer).withdraw(amount))
        .to.emit(rewardsVault, "Withdrawal")
        .withArgs(foundation.address, amount);
    });

    it("[REQ-2] stranger without TREASURER_ROLE cannot withdraw", async () => {
      await expect(
        rewardsVault.connect(stranger).withdraw(parseEther("0.1"))
      ).to.be.reverted;
    });

    it("[REQ-2] admin without TREASURER_ROLE cannot withdraw", async () => {
      await expect(
        rewardsVault.connect(admin).withdraw(parseEther("0.1"))
      ).to.be.reverted;
    });

    it("[REQ-2] pauser without TREASURER_ROLE cannot withdraw", async () => {
      await expect(
        rewardsVault.connect(pauser).withdraw(parseEther("0.1"))
      ).to.be.reverted;
    });

    it("reverts when withdrawal amount exceeds vault balance", async () => {
      await expect(
        rewardsVault.connect(treasurer).withdraw(parseEther("999"))
      ).to.be.reverted;
    });

    it("reverts on zero amount", async () => {
      await expect(
        rewardsVault.connect(treasurer).withdraw(0)
      ).to.be.reverted;
    });

    it("vault balance decreases correctly after withdrawal", async () => {
      const amount = parseEther("0.4");
      await expect(
        rewardsVault.connect(treasurer).withdraw(amount)
      ).to.changeEtherBalance(rewardsVault, -amount);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. pause() / unpause() — Required Test 3
  // ═══════════════════════════════════════════════════════════════════════════
  describe("pause() / unpause()", () => {
    beforeEach(async () => {
      // Fund vault
      await rewardsVault.connect(donor).donate({ value: parseEther("1") });
    });

    it("[REQ-3] when vault is paused, donate() reverts", async () => {
      await rewardsVault.connect(pauser).pause();
      await expect(
        rewardsVault.connect(donor).donate({ value: parseEther("0.01") })
      ).to.be.reverted;
    });

    it("[REQ-3] when vault is paused, withdraw() reverts", async () => {
      await rewardsVault.connect(pauser).pause();
      await expect(
        rewardsVault.connect(treasurer).withdraw(parseEther("0.1"))
      ).to.be.reverted;
    });

    it("[REQ-3] after unpause, donate() works again", async () => {
      await rewardsVault.connect(pauser).pause();
      await rewardsVault.connect(pauser).unpause();
      await expect(
        rewardsVault.connect(donor).donate({ value: parseEther("0.01") })
      ).to.changeTokenBalance(communityToken, donor, parseEther("1"));
    });

    it("[REQ-3] after unpause, withdraw() works again", async () => {
      await rewardsVault.connect(pauser).pause();
      await rewardsVault.connect(pauser).unpause();
      await expect(
        rewardsVault.connect(treasurer).withdraw(parseEther("0.5"))
      ).to.changeEtherBalance(foundation, parseEther("0.5"));
    });

    it("auditor (AUDITOR_ROLE == PAUSER_ROLE) can pause the vault", async () => {
      await rewardsVault.connect(auditor).pause();
      expect(await rewardsVault.paused()).to.be.true;
    });

    it("auditor can unpause the vault", async () => {
      await rewardsVault.connect(auditor).pause();
      await rewardsVault.connect(auditor).unpause();
      expect(await rewardsVault.paused()).to.be.false;
    });

    it("stranger cannot pause the vault", async () => {
      await expect(rewardsVault.connect(stranger).pause()).to.be.reverted;
    });

    it("treasurer (without PAUSER_ROLE) cannot pause the vault", async () => {
      await expect(rewardsVault.connect(treasurer).pause()).to.be.reverted;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. CommunityToken — independent unit tests
  // ═══════════════════════════════════════════════════════════════════════════
  describe("CommunityToken", () => {
    it("stranger cannot call mint()", async () => {
      await expect(
        communityToken.connect(stranger).mint(stranger.address, parseEther("1"))
      ).to.be.reverted;
    });

    it("token holder can burn their own tokens", async () => {
      // Vault is the minter; donate to get tokens
      await rewardsVault.connect(donor).donate({ value: parseEther("0.1") });
      const bal = await communityToken.balanceOf(donor.address);
      expect(bal).to.equal(parseEther("10"));

      await communityToken.connect(donor).burn(parseEther("5"));
      expect(await communityToken.balanceOf(donor.address)).to.equal(parseEther("5"));
    });

    it("burn reverts if amount exceeds balance", async () => {
      await expect(
        communityToken.connect(stranger).burn(parseEther("1"))
      ).to.be.reverted;
    });

    it("pauser can pause the token contract", async () => {
      await communityToken.connect(pauser).pause();
      expect(await communityToken.paused()).to.be.true;
    });

    it("pauser can unpause the token contract", async () => {
      await communityToken.connect(pauser).pause();
      await communityToken.connect(pauser).unpause();
      expect(await communityToken.paused()).to.be.false;
    });

    it("pausing token contract blocks transfers", async () => {
      await rewardsVault.connect(donor).donate({ value: parseEther("0.01") });
      await communityToken.connect(pauser).pause();
      await expect(
        communityToken.connect(donor).transfer(stranger.address, parseEther("1"))
      ).to.be.reverted;
    });

    it("stranger cannot pause token contract", async () => {
      await expect(communityToken.connect(stranger).pause()).to.be.reverted;
    });

    it("admin can grant MINTER_ROLE to another address", async () => {
      const MINTER_ROLE = await communityToken.MINTER_ROLE();
      await communityToken.connect(admin).grantRole(MINTER_ROLE, stranger.address);
      // stranger can now mint
      await communityToken.connect(stranger).mint(donor.address, parseEther("1"));
      expect(await communityToken.balanceOf(donor.address)).to.equal(parseEther("1"));
    });

    it("admin can revoke MINTER_ROLE", async () => {
      const MINTER_ROLE = await communityToken.MINTER_ROLE();
      // Revoke vault's minter role
      await communityToken.connect(admin).revokeRole(MINTER_ROLE, await rewardsVault.getAddress());
      // Donation should now fail (vault can't mint)
      await expect(
        rewardsVault.connect(donor).donate({ value: parseEther("0.01") })
      ).to.be.reverted;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. setFoundationWallet()
  // ═══════════════════════════════════════════════════════════════════════════
  describe("setFoundationWallet()", () => {
    it("admin can update the foundation wallet", async () => {
      await rewardsVault.connect(admin).setFoundationWallet(stranger.address);
      expect(await rewardsVault.foundationWallet()).to.equal(stranger.address);
    });

    it("emits FoundationWalletUpdated event", async () => {
      await expect(rewardsVault.connect(admin).setFoundationWallet(stranger.address))
        .to.emit(rewardsVault, "FoundationWalletUpdated")
        .withArgs(foundation.address, stranger.address);
    });

    it("reverts on zero address", async () => {
      await expect(
        rewardsVault.connect(admin).setFoundationWallet(ZeroAddress)
      ).to.be.reverted;
    });

    it("stranger cannot update foundation wallet", async () => {
      await expect(
        rewardsVault.connect(stranger).setFoundationWallet(stranger.address)
      ).to.be.reverted;
    });

    it("treasurer cannot update foundation wallet", async () => {
      await expect(
        rewardsVault.connect(treasurer).setFoundationWallet(stranger.address)
      ).to.be.reverted;
    });

    it("after wallet update, treasurer withdraws to new wallet", async () => {
      await rewardsVault.connect(donor).donate({ value: parseEther("1") });
      await rewardsVault.connect(admin).setFoundationWallet(stranger.address);
      const amount = parseEther("0.5");
      await expect(
        rewardsVault.connect(treasurer).withdraw(amount)
      ).to.changeEtherBalance(stranger, amount);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. Accidental ETH transfers — receive() / fallback()
  // ═══════════════════════════════════════════════════════════════════════════
  describe("Direct ETH transfer blocking", () => {
    it("plain ETH send (receive) reverts", async () => {
      await expect(
        donor.sendTransaction({ to: await rewardsVault.getAddress(), value: parseEther("1") })
      ).to.be.reverted;
    });

    it("call with unknown selector (fallback) reverts", async () => {
      await expect(
        donor.sendTransaction({
          to: await rewardsVault.getAddress(),
          value: parseEther("0.01"),
          data: "0xdeadbeef",
        })
      ).to.be.reverted;
    });
  });
});
