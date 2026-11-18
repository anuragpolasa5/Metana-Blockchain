// test/TokenSale.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("TokenSale", function () {
  // ─── Helpers ──────────────────────────────────────────────────────────────
  const BUY_PRICE  = ethers.parseEther("0.001");   // per whole token
  const SELL_PRICE = ethers.parseEther("0.0005");  // per whole token
  const DECIMALS   = 18n;
  const ONE_TOKEN  = 10n ** DECIMALS;
  const MAX_SUPPLY_UNITS = 1_000_000n;

  // ─── Fixture ──────────────────────────────────────────────────────────────
  async function deployFixture() {
    const [owner, buyer, seller, other] = await ethers.getSigners();

    // Deploy token
    const LearnToken = await ethers.getContractFactory("LearnToken");
    const token = await LearnToken.deploy("LearnToken", "LRN", 18, MAX_SUPPLY_UNITS, owner.address);

    // Deploy sale
    const TokenSale = await ethers.getContractFactory("TokenSale");
    const sale = await TokenSale.deploy(await token.getAddress(), SELL_PRICE, BUY_PRICE, owner.address);

    // Grant MINTER_ROLE
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.connect(owner).grantRole(MINTER_ROLE, await sale.getAddress());

    return { token, sale, owner, buyer, seller, other, MINTER_ROLE };
  }

  // ─── Deployment ───────────────────────────────────────────────────────────
  describe("Deployment (FE-4, FE-5)", function () {
    it("Should set token address", async function () {
      const { token, sale } = await loadFixture(deployFixture);
      expect(await sale.token()).to.equal(await token.getAddress());
    });

    it("Should set buyPrice and sellPrice", async function () {
      const { sale } = await loadFixture(deployFixture);
      expect(await sale.buyPrice()).to.equal(BUY_PRICE);
      expect(await sale.sellPrice()).to.equal(SELL_PRICE);
    });

    it("Should set deployer as owner (FE-4)", async function () {
      const { sale, owner } = await loadFixture(deployFixture);
      expect(await sale.owner()).to.equal(owner.address);
    });

    it("Should revert with zero address token", async function () {
      const { owner } = await loadFixture(deployFixture);
      const TokenSale = await ethers.getContractFactory("TokenSale");
      await expect(
        TokenSale.deploy(ethers.ZeroAddress, SELL_PRICE, BUY_PRICE, owner.address)
      ).to.be.revertedWithCustomError(await ethers.getContractFactory("TokenSale"), "InvalidAddress");
    });

    it("Should revert if sellPrice >= buyPrice", async function () {
      const { token, owner } = await loadFixture(deployFixture);
      const TokenSale = await ethers.getContractFactory("TokenSale");
      await expect(
        TokenSale.deploy(await token.getAddress(), BUY_PRICE, BUY_PRICE, owner.address)
      ).to.be.revertedWithCustomError(TokenSale, "InvalidPrice");
    });
  });

  // ─── Buy Tokens ───────────────────────────────────────────────────────────
  describe("buyTokens() (FE-7)", function () {
    it("Should mint tokens to buyer (no reserve)", async function () {
      const { token, sale, buyer } = await loadFixture(deployFixture);

      // Buy 10 tokens
      const ethToSend = BUY_PRICE * 10n;
      await sale.connect(buyer).buyTokens({ value: ethToSend });

      expect(await token.balanceOf(buyer.address)).to.equal(10n * ONE_TOKEN);
    });

    it("Should use reserves before minting", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);

      // Seed contract with 5 tokens
      const saleAddr = await sale.getAddress();
      const MINTER_ROLE = await token.MINTER_ROLE();
      // Already granted in fixture; mint directly to sale contract
      await token.connect(owner).grantRole(MINTER_ROLE, owner.address);
      await token.connect(owner).mint(saleAddr, 5n * ONE_TOKEN);

      const reserveBefore = await sale.tokenReserve();
      expect(reserveBefore).to.equal(5n * ONE_TOKEN);

      // Buy 5 tokens – should use reserve, not mint
      const supplyBefore = await token.totalSupply();
      await sale.connect(buyer).buyTokens({ value: BUY_PRICE * 5n });

      const supplyAfter = await token.totalSupply();
      // Supply should not have increased (only reserve used)
      expect(supplyAfter).to.equal(supplyBefore);
      expect(await sale.tokenReserve()).to.equal(0n);
      expect(await token.balanceOf(buyer.address)).to.equal(5n * ONE_TOKEN);
    });

    it("Should use partial reserve and mint remainder", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);

      const saleAddr = await sale.getAddress();
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(saleAddr, 3n * ONE_TOKEN); // 3 reserve

      const supplyBefore = await token.totalSupply();
      // Buy 8 tokens: 3 from reserve, 5 minted
      await sale.connect(buyer).buyTokens({ value: BUY_PRICE * 8n });

      expect(await token.balanceOf(buyer.address)).to.equal(8n * ONE_TOKEN);
      // 5 new tokens minted (reserve 3 + mint 5 = 8)
      expect(await token.totalSupply()).to.equal(supplyBefore + 5n * ONE_TOKEN);
    });

    it("Should accept ETH via receive() fallback (FE-7)", async function () {
      const { token, sale, buyer } = await loadFixture(deployFixture);

      // Send ETH directly to the contract (not calling buyTokens)
      await buyer.sendTransaction({
        to: await sale.getAddress(),
        value: BUY_PRICE * 5n,
      });

      expect(await token.balanceOf(buyer.address)).to.equal(5n * ONE_TOKEN);
    });

    it("Should emit TokensPurchased event", async function () {
      const { sale, buyer } = await loadFixture(deployFixture);

      await expect(
        sale.connect(buyer).buyTokens({ value: BUY_PRICE * 3n })
      ).to.emit(sale, "TokensPurchased")
        .withArgs(buyer.address, 3n * ONE_TOKEN, BUY_PRICE * 3n);
    });

    it("Should revert with zero ETH (FE-7)", async function () {
      const { sale, buyer } = await loadFixture(deployFixture);
      await expect(
        sale.connect(buyer).buyTokens({ value: 0 })
      ).to.be.revertedWithCustomError(sale, "ZeroAmount");
    });

    it("Should revert if purchase would exceed MAX_SUPPLY (FE-16 guard)", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);

      // Mint almost entire supply to buyer
      const almostAll = (MAX_SUPPLY_UNITS - 1n) * ONE_TOKEN;
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(buyer.address, almostAll);

      // Try to buy 2 tokens (would exceed cap by 1)
      await expect(
        sale.connect(buyer).buyTokens({ value: BUY_PRICE * 2n })
      ).to.be.revertedWithCustomError(sale, "MaxSupplyExceeded");
    });
  });

  // ─── Sell Tokens ──────────────────────────────────────────────────────────
  describe("sellTokens() (FE-8, FE-17)", function () {
    // Helper: buy tokens first
    async function buyTokens(sale, signer, count) {
      await sale.connect(signer).buyTokens({ value: BUY_PRICE * BigInt(count) });
    }

    it("Should sell tokens and receive ETH", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);

      // Fund sale with ETH so it can pay sellers
      await owner.sendTransaction({ to: await sale.getAddress(), value: ethers.parseEther("1") });

      // Give buyer some tokens first
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(buyer.address, 10n * ONE_TOKEN);

      // Approve and sell 5 tokens
      await token.connect(buyer).approve(await sale.getAddress(), 5n * ONE_TOKEN);

      const balanceBefore = await ethers.provider.getBalance(buyer.address);
      const tx = await sale.connect(buyer).sellTokens(5n * ONE_TOKEN);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(buyer.address);

      const expectedETH = SELL_PRICE * 5n;
      expect(balanceAfter).to.equal(balanceBefore + expectedETH - gasUsed);
      expect(await token.balanceOf(buyer.address)).to.equal(5n * ONE_TOKEN);
      // Tokens transferred to contract (reserve)
      expect(await sale.tokenReserve()).to.equal(5n * ONE_TOKEN);
    });

    it("Should emit TokensSold event", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);
      await owner.sendTransaction({ to: await sale.getAddress(), value: ethers.parseEther("1") });
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(buyer.address, 5n * ONE_TOKEN);
      await token.connect(buyer).approve(await sale.getAddress(), 5n * ONE_TOKEN);

      await expect(
        sale.connect(buyer).sellTokens(5n * ONE_TOKEN)
      ).to.emit(sale, "TokensSold")
        .withArgs(buyer.address, 5n * ONE_TOKEN, SELL_PRICE * 5n);
    });

    it("Should revert if contract has insufficient ETH (FE-17)", async function () {
      const { token, sale, owner, buyer } = await loadFixture(deployFixture);
      // Do NOT fund the sale contract with ETH

      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(buyer.address, 5n * ONE_TOKEN);
      await token.connect(buyer).approve(await sale.getAddress(), 5n * ONE_TOKEN);

      await expect(
        sale.connect(buyer).sellTokens(5n * ONE_TOKEN)
      ).to.be.revertedWithCustomError(sale, "InsufficientETHReserves");
    });

    it("Should revert with zero amount", async function () {
      const { sale, buyer } = await loadFixture(deployFixture);
      await expect(
        sale.connect(buyer).sellTokens(0n)
      ).to.be.revertedWithCustomError(sale, "ZeroAmount");
    });
  });

  // ─── Owner Withdrawals ────────────────────────────────────────────────────
  describe("withdrawTokens() (FE-9)", function () {
    it("Should allow owner to withdraw tokens", async function () {
      const { token, sale, owner } = await loadFixture(deployFixture);
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(await sale.getAddress(), 10n * ONE_TOKEN);

      await sale.connect(owner).withdrawTokens(10n * ONE_TOKEN);
      expect(await token.balanceOf(owner.address)).to.equal(10n * ONE_TOKEN);
    });

    it("Should revert if non-owner calls withdrawTokens (FE-9)", async function () {
      const { token, sale, owner, other } = await loadFixture(deployFixture);
      await token.connect(owner).grantRole(await token.MINTER_ROLE(), owner.address);
      await token.connect(owner).mint(await sale.getAddress(), 10n * ONE_TOKEN);

      await expect(
        sale.connect(other).withdrawTokens(10n * ONE_TOKEN)
      ).to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
    });

    it("Should revert if insufficient token balance", async function () {
      const { sale, owner } = await loadFixture(deployFixture);
      await expect(
        sale.connect(owner).withdrawTokens(1n * ONE_TOKEN)
      ).to.be.revertedWithCustomError(sale, "InsufficientTokenBalance");
    });
  });

  describe("withdrawETH() (FE-10)", function () {
    it("Should allow owner to withdraw ETH", async function () {
      const { sale, owner } = await loadFixture(deployFixture);
      const fundAmount = ethers.parseEther("1");
      await owner.sendTransaction({ to: await sale.getAddress(), value: fundAmount });

      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);
      const tx = await sale.connect(owner).withdrawETH(fundAmount);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      expect(ownerBalanceAfter).to.equal(ownerBalanceBefore + fundAmount - gasUsed);
    });

    it("Should revert if non-owner calls withdrawETH (FE-10)", async function () {
      const { sale, owner, other } = await loadFixture(deployFixture);
      await owner.sendTransaction({ to: await sale.getAddress(), value: ethers.parseEther("1") });

      await expect(
        sale.connect(other).withdrawETH(ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
    });

    it("Should revert if insufficient ETH balance", async function () {
      const { sale, owner } = await loadFixture(deployFixture);
      await expect(
        sale.connect(owner).withdrawETH(ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(sale, "InsufficientETHReserves");
    });
  });

  // ─── Ownable2Step (FE-4) ──────────────────────────────────────────────────
  describe("Ownable2Step (FE-4)", function () {
    it("Should require a two-step ownership transfer", async function () {
      const { sale, owner, other } = await loadFixture(deployFixture);

      // Initiate transfer
      await sale.connect(owner).transferOwnership(other.address);
      // Still original owner
      expect(await sale.owner()).to.equal(owner.address);
      expect(await sale.pendingOwner()).to.equal(other.address);

      // New owner must accept
      await sale.connect(other).acceptOwnership();
      expect(await sale.owner()).to.equal(other.address);
    });
  });

  // ─── MINTER_ROLE grant (FE-6) ─────────────────────────────────────────────
  describe("MINTER_ROLE (FE-6)", function () {
    it("TokenSale should hold MINTER_ROLE in LearnToken", async function () {
      const { token, sale, MINTER_ROLE } = await loadFixture(deployFixture);
      expect(await token.hasRole(MINTER_ROLE, await sale.getAddress())).to.be.true;
    });
  });
});
