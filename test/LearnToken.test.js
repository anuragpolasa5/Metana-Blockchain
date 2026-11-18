// test/LearnToken.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("LearnToken", function () {
  // ─── Fixture ──────────────────────────────────────────────────────────────
  async function deployLearnTokenFixture() {
    const [admin, minter, user1, user2] = await ethers.getSigners();

    const MAX_SUPPLY_UNITS = 1_000_000n; // 1 million
    const LearnToken = await ethers.getContractFactory("LearnToken");
    const token = await LearnToken.deploy("LearnToken", "LRN", 18, MAX_SUPPLY_UNITS, admin.address);

    const MINTER_ROLE = await token.MINTER_ROLE();
    const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();

    return { token, admin, minter, user1, user2, MAX_SUPPLY_UNITS, MINTER_ROLE, DEFAULT_ADMIN_ROLE };
  }

  // ─── Deployment ───────────────────────────────────────────────────────────
  describe("Deployment", function () {
    it("Should set correct name and symbol", async function () {
      const { token } = await loadFixture(deployLearnTokenFixture);
      expect(await token.name()).to.equal("LearnToken");
      expect(await token.symbol()).to.equal("LRN");
    });

    it("Should have 18 decimals", async function () {
      const { token } = await loadFixture(deployLearnTokenFixture);
      expect(await token.decimals()).to.equal(18);
    });

    it("Should set MAX_SUPPLY correctly (FE-1)", async function () {
      const { token, MAX_SUPPLY_UNITS } = await loadFixture(deployLearnTokenFixture);
      const expectedCap = MAX_SUPPLY_UNITS * 10n ** 18n;
      expect(await token.maxSupply()).to.equal(expectedCap);
      expect(await token.cap()).to.equal(expectedCap);
    });

    it("Should start with zero total supply", async function () {
      const { token } = await loadFixture(deployLearnTokenFixture);
      expect(await token.totalSupply()).to.equal(0n);
    });

    it("Should grant DEFAULT_ADMIN_ROLE to admin (FE-3)", async function () {
      const { token, admin, DEFAULT_ADMIN_ROLE } = await loadFixture(deployLearnTokenFixture);
      expect(await token.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
    });
  });

  // ─── Access Control ───────────────────────────────────────────────────────
  describe("Access Control (FE-3)", function () {
    it("Should allow admin to grant MINTER_ROLE", async function () {
      const { token, admin, minter, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);
      expect(await token.hasRole(MINTER_ROLE, minter.address)).to.be.true;
    });

    it("Should reject minting from account without MINTER_ROLE", async function () {
      const { token, user1, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await expect(
        token.connect(user1).mint(user1.address, ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(token, "AccessControlUnauthorizedAccount")
        .withArgs(user1.address, MINTER_ROLE);
    });

    it("Should allow MINTER_ROLE to mint tokens", async function () {
      const { token, admin, minter, user1, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      const mintAmount = ethers.parseEther("500");
      await token.connect(minter).mint(user1.address, mintAmount);
      expect(await token.balanceOf(user1.address)).to.equal(mintAmount);
      expect(await token.totalSupply()).to.equal(mintAmount);
    });

    it("Should allow admin to revoke MINTER_ROLE", async function () {
      const { token, admin, minter, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);
      await token.connect(admin).revokeRole(MINTER_ROLE, minter.address);
      expect(await token.hasRole(MINTER_ROLE, minter.address)).to.be.false;
    });
  });

  // ─── Supply Cap ───────────────────────────────────────────────────────────
  describe("Supply Cap enforcement via _update() (FE-2)", function () {
    it("Should mint up to MAX_SUPPLY without reverting", async function () {
      const { token, admin, minter, user1, MINTER_ROLE, MAX_SUPPLY_UNITS } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      const fullCap = MAX_SUPPLY_UNITS * 10n ** 18n;
      await token.connect(minter).mint(user1.address, fullCap);
      expect(await token.totalSupply()).to.equal(fullCap);
    });

    it("Should revert when minting beyond MAX_SUPPLY (FE-2)", async function () {
      const { token, admin, minter, user1, MINTER_ROLE, MAX_SUPPLY_UNITS } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      const fullCap = MAX_SUPPLY_UNITS * 10n ** 18n;
      await token.connect(minter).mint(user1.address, fullCap);

      // Try to mint 1 more wei
      await expect(
        token.connect(minter).mint(user1.address, 1n)
      ).to.be.revertedWithCustomError(token, "ERC20ExceededCap");
    });

    it("Should revert on partial mint that would exceed cap", async function () {
      const { token, admin, minter, user1, MINTER_ROLE, MAX_SUPPLY_UNITS } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      // Mint 999,999 tokens then try to mint 2 tokens (should exceed by 1)
      const almostFull = (MAX_SUPPLY_UNITS - 1n) * 10n ** 18n;
      await token.connect(minter).mint(user1.address, almostFull);

      await expect(
        token.connect(minter).mint(user1.address, 2n * 10n ** 18n)
      ).to.be.revertedWithCustomError(token, "ERC20ExceededCap");
    });
  });

  // ─── ERC20 Standard Behaviour ─────────────────────────────────────────────
  describe("ERC20 standard behaviour", function () {
    it("Should transfer tokens between accounts", async function () {
      const { token, admin, minter, user1, user2, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      const amount = ethers.parseEther("100");
      await token.connect(minter).mint(user1.address, amount);
      await token.connect(user1).transfer(user2.address, amount);
      expect(await token.balanceOf(user2.address)).to.equal(amount);
      expect(await token.balanceOf(user1.address)).to.equal(0n);
    });

    it("Should handle allowance correctly", async function () {
      const { token, admin, minter, user1, user2, MINTER_ROLE } = await loadFixture(deployLearnTokenFixture);
      await token.connect(admin).grantRole(MINTER_ROLE, minter.address);

      const amount = ethers.parseEther("100");
      await token.connect(minter).mint(user1.address, amount);
      await token.connect(user1).approve(user2.address, amount);
      expect(await token.allowance(user1.address, user2.address)).to.equal(amount);

      await token.connect(user2).transferFrom(user1.address, user2.address, amount);
      expect(await token.balanceOf(user2.address)).to.equal(amount);
    });
  });
});
