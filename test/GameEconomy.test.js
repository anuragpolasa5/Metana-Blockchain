// test/GameEconomy.test.js
// Comprehensive test suite for GameEconomyV1 and GameEconomyV2.
// Uses EIP-1967 Transparent Proxy pattern.

const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────
const CURRENCY_ID = 0n;
const MAT_1 = 1n;
const MAT_2 = 2n;
const MAT_3 = 3n;
const CURRENCY_PRICE = ethers.parseEther("0.001"); // per unit
const BASE_URI = "https://game.example.com/api/token/{id}.json";

async function deployV1(admin) {
  const GameEconomyV1 = await ethers.getContractFactory("GameEconomyV1");
  const proxy = await upgrades.deployProxy(
    GameEconomyV1,
    [BASE_URI, admin.address],
    { kind: "transparent", initializer: "initialize" }
  );
  await proxy.waitForDeployment();
  return proxy;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Test Suite
// ─────────────────────────────────────────────────────────────────────────────
describe("GameEconomy", function () {
  let proxy, admin, user, user2;

  beforeEach(async () => {
    [admin, user, user2] = await ethers.getSigners();
    proxy = await deployV1(admin);

    // Pre-configure prices and one recipe for most tests
    await proxy.setMaterialPrice(MAT_1, 10n);   // 10 currency/unit
    await proxy.setMaterialPrice(MAT_2, 20n);   // 20 currency/unit
    await proxy.setMaterialPrice(MAT_3, 5n);    // 5 currency/unit
    await proxy.setRecipe([MAT_1, MAT_2], [2n, 1n]);  // needs 2× mat1, 1× mat2
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-1  Initialization
  // ───────────────────────────────────────────────────────────────────────────
  describe("Initialization", () => {
    it("sets nextUniqueId to 1000", async () => {
      expect(await proxy.nextUniqueId()).to.equal(1000n);
    });

    it("grants all roles to admin", async () => {
      const PAUSER = await proxy.PAUSER_ROLE();
      const GAME_ADMIN = await proxy.GAME_ADMIN_ROLE();
      const DEFAULT_ADMIN = await proxy.DEFAULT_ADMIN_ROLE();

      expect(await proxy.hasRole(DEFAULT_ADMIN, admin.address)).to.be.true;
      expect(await proxy.hasRole(PAUSER, admin.address)).to.be.true;
      expect(await proxy.hasRole(GAME_ADMIN, admin.address)).to.be.true;
    });

    it("cannot initialize twice", async () => {
      await expect(
        proxy.initialize(BASE_URI, admin.address)
      ).to.be.revertedWithCustomError(proxy, "InvalidInitialization");
    });

    it("uses EIP-1967 Transparent Proxy with ProxyAdmin", async () => {
      const proxyAddress = await proxy.getAddress();
      const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);
      expect(adminAddress).to.not.equal(ethers.ZeroAddress);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-3  Currency Acquisition
  // ───────────────────────────────────────────────────────────────────────────
  describe("buyCurrency (GE-3)", () => {
    it("mints correct amount of currency ID 0", async () => {
      const amount = 5n;
      await proxy.connect(user).buyCurrency(amount, { value: amount * CURRENCY_PRICE });
      expect(await proxy.balanceOf(user.address, CURRENCY_ID)).to.equal(amount);
    });

    it("emits CurrencyBought event", async () => {
      const amount = 3n;
      await expect(
        proxy.connect(user).buyCurrency(amount, { value: amount * CURRENCY_PRICE })
      )
        .to.emit(proxy, "CurrencyBought")
        .withArgs(user.address, amount, amount * CURRENCY_PRICE);
    });

    it("reverts on underpayment", async () => {
      await expect(
        proxy.connect(user).buyCurrency(5n, { value: ethers.parseEther("0.001") })
      ).to.be.revertedWith("GameEconomy: incorrect ETH amount");
    });

    it("reverts on overpayment", async () => {
      await expect(
        proxy.connect(user).buyCurrency(1n, { value: ethers.parseEther("1") })
      ).to.be.revertedWith("GameEconomy: incorrect ETH amount");
    });

    it("reverts on zero amount", async () => {
      await expect(
        proxy.connect(user).buyCurrency(0n, { value: 0n })
      ).to.be.revertedWith("GameEconomy: amount must be > 0");
    });

    it("accumulates ETH in the contract", async () => {
      const amount = 10n;
      const ethToSend = amount * CURRENCY_PRICE;
      await proxy.connect(user).buyCurrency(amount, { value: ethToSend });
      expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(ethToSend);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-4  Admin Withdrawals
  // ───────────────────────────────────────────────────────────────────────────
  describe("withdraw (GE-4)", () => {
    beforeEach(async () => {
      await proxy.connect(user).buyCurrency(10n, { value: 10n * CURRENCY_PRICE });
    });

    it("allows admin to withdraw ETH", async () => {
      const contractBal = await ethers.provider.getBalance(await proxy.getAddress());
      const adminBefore = await ethers.provider.getBalance(admin.address);

      const tx = await proxy.connect(admin).withdraw(admin.address, contractBal);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * tx.gasPrice;

      const adminAfter = await ethers.provider.getBalance(admin.address);
      expect(adminAfter).to.be.closeTo(adminBefore + contractBal - gasUsed, ethers.parseEther("0.0001"));
    });

    it("emits Withdrawn event", async () => {
      const contractBal = await ethers.provider.getBalance(await proxy.getAddress());
      await expect(proxy.connect(admin).withdraw(admin.address, contractBal))
        .to.emit(proxy, "Withdrawn")
        .withArgs(admin.address, contractBal);
    });

    it("reverts for non-admin", async () => {
      await expect(
        proxy.connect(user).withdraw(user.address, 1n)
      ).to.be.reverted;
    });

    it("reverts on insufficient balance", async () => {
      const tooMuch = ethers.parseEther("999");
      await expect(
        proxy.connect(admin).withdraw(admin.address, tooMuch)
      ).to.be.revertedWith("GameEconomy: insufficient balance");
    });

    it("reverts on zero address", async () => {
      await expect(
        proxy.connect(admin).withdraw(ethers.ZeroAddress, 1n)
      ).to.be.revertedWith("GameEconomy: zero address");
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-5  Material Pricing
  // ───────────────────────────────────────────────────────────────────────────
  describe("setMaterialPrice (GE-5)", () => {
    it("sets and retrieves price", async () => {
      await proxy.setMaterialPrice(MAT_1, 99n);
      expect(await proxy.materialPrice(MAT_1)).to.equal(99n);
    });

    it("emits MaterialPriceSet", async () => {
      await expect(proxy.setMaterialPrice(MAT_2, 50n))
        .to.emit(proxy, "MaterialPriceSet")
        .withArgs(MAT_2, 50n);
    });

    it("reverts for non-admin", async () => {
      await expect(proxy.connect(user).setMaterialPrice(MAT_1, 10n)).to.be.reverted;
    });

    it("reverts for ID 0 (currency)", async () => {
      await expect(proxy.setMaterialPrice(0n, 10n)).to.be.revertedWith(
        "GameEconomy: invalid material ID"
      );
    });

    it("reverts for crafted item IDs (>= 1000)", async () => {
      await expect(proxy.setMaterialPrice(1000n, 10n)).to.be.revertedWith(
        "GameEconomy: invalid material ID"
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-6  Material Purchase
  // ───────────────────────────────────────────────────────────────────────────
  describe("buyMaterial (GE-6)", () => {
    beforeEach(async () => {
      // Give user 100 currency
      await proxy.connect(user).buyCurrency(100n, { value: 100n * CURRENCY_PRICE });
    });

    it("burns currency and mints material", async () => {
      const currencyBefore = await proxy.balanceOf(user.address, CURRENCY_ID);
      await proxy.connect(user).buyMaterial(MAT_1, 3n);
      // cost = 3 * 10 = 30 currency burned
      expect(await proxy.balanceOf(user.address, CURRENCY_ID)).to.equal(currencyBefore - 30n);
      expect(await proxy.balanceOf(user.address, MAT_1)).to.equal(3n);
    });

    it("emits MaterialPurchased event", async () => {
      await expect(proxy.connect(user).buyMaterial(MAT_1, 2n))
        .to.emit(proxy, "MaterialPurchased")
        .withArgs(user.address, MAT_1, 2n);
    });

    it("reverts on insufficient currency", async () => {
      await expect(
        proxy.connect(user).buyMaterial(MAT_2, 6n)
      ).to.be.revertedWith("GameEconomy: insufficient currency");
    });

    it("reverts on unpriced material", async () => {
      await expect(
        proxy.connect(user).buyMaterial(50n, 1n)
      ).to.be.revertedWith("GameEconomy: material not for sale");
    });

    it("reverts on zero amount", async () => {
      await expect(
        proxy.connect(user).buyMaterial(MAT_1, 0n)
      ).to.be.revertedWith("GameEconomy: amount must be > 0");
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-7  Craft Recipes
  // ───────────────────────────────────────────────────────────────────────────
  describe("setRecipe (GE-7)", () => {
    it("stores recipe correctly", async () => {
      expect(await proxy.recipe(MAT_1)).to.equal(2n);
      expect(await proxy.recipe(MAT_2)).to.equal(1n);
    });

    it("emits RecipeSet event", async () => {
      await expect(proxy.setRecipe([MAT_3], [4n]))
        .to.emit(proxy, "RecipeSet")
        .withArgs([MAT_3], [4n]);
    });

    it("replaces old recipe", async () => {
      await proxy.setRecipe([MAT_3], [4n]);
      expect(await proxy.recipe(MAT_1)).to.equal(0n);
      expect(await proxy.recipe(MAT_2)).to.equal(0n);
      expect(await proxy.recipe(MAT_3)).to.equal(4n);
    });

    it("reverts on length mismatch", async () => {
      await expect(
        proxy.setRecipe([MAT_1, MAT_2], [1n])
      ).to.be.revertedWith("GameEconomy: length mismatch");
    });

    it("reverts on empty recipe", async () => {
      await expect(proxy.setRecipe([], [])).to.be.revertedWith("GameEconomy: empty recipe");
    });

    it("reverts for non-admin", async () => {
      await expect(proxy.connect(user).setRecipe([MAT_1], [1n])).to.be.reverted;
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-8  Crafting
  // ───────────────────────────────────────────────────────────────────────────
  describe("craft (GE-8)", () => {
    beforeEach(async () => {
      await proxy.connect(user).buyCurrency(200n, { value: 200n * CURRENCY_PRICE });
      await proxy.connect(user).buyMaterial(MAT_1, 2n);
      await proxy.connect(user).buyMaterial(MAT_2, 1n);
    });

    it("burns materials and mints unique item (supply 1)", async () => {
      const nextId = await proxy.nextUniqueId();
      await proxy.connect(user).craft();

      expect(await proxy.balanceOf(user.address, MAT_1)).to.equal(0n);
      expect(await proxy.balanceOf(user.address, MAT_2)).to.equal(0n);
      expect(await proxy.balanceOf(user.address, nextId)).to.equal(1n);
    });

    it("increments nextUniqueId after craft", async () => {
      const before = await proxy.nextUniqueId();
      await proxy.connect(user).craft();
      expect(await proxy.nextUniqueId()).to.equal(before + 1n);
    });

    it("emits Crafted event with correct ID", async () => {
      const nextId = await proxy.nextUniqueId();
      await expect(proxy.connect(user).craft())
        .to.emit(proxy, "Crafted")
        .withArgs(user.address, nextId);
    });

    it("mints different IDs for successive crafts", async () => {
      const id1 = await proxy.nextUniqueId();
      await proxy.connect(user).craft();

      await proxy.connect(user).buyMaterial(MAT_1, 2n);
      await proxy.connect(user).buyMaterial(MAT_2, 1n);

      const id2 = await proxy.nextUniqueId();
      await proxy.connect(user).craft();

      expect(id2).to.equal(id1 + 1n);
      expect(await proxy.balanceOf(user.address, id1)).to.equal(1n);
      expect(await proxy.balanceOf(user.address, id2)).to.equal(1n);
    });

    it("reverts when caller lacks required materials", async () => {
      await expect(proxy.connect(user2).craft()).to.be.revertedWith(
        "GameEconomy: insufficient materials"
      );
    });

    it("reverts when no active recipe", async () => {
      const GameEconomyV1 = await ethers.getContractFactory("GameEconomyV1");
      const freshProxy = await upgrades.deployProxy(
        GameEconomyV1,
        [BASE_URI, admin.address],
        { kind: "transparent", initializer: "initialize" }
      );
      await freshProxy.waitForDeployment();
      await expect(freshProxy.connect(user).craft()).to.be.revertedWith(
        "GameEconomy: no active recipe"
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  GE-2  Pause Control
  // ───────────────────────────────────────────────────────────────────────────
  describe("Pause Control (GE-2)", () => {
    it("admin can pause and unpause", async () => {
      await proxy.pause();
      expect(await proxy.paused()).to.be.true;
      await proxy.unpause();
      expect(await proxy.paused()).to.be.false;
    });

    it("pause blocks buyCurrency", async () => {
      await proxy.pause();
      await expect(
        proxy.connect(user).buyCurrency(1n, { value: CURRENCY_PRICE })
      ).to.be.revertedWithCustomError(proxy, "EnforcedPause");
    });

    it("pause blocks buyMaterial", async () => {
      await proxy.connect(user).buyCurrency(100n, { value: 100n * CURRENCY_PRICE });
      await proxy.pause();
      await expect(
        proxy.connect(user).buyMaterial(MAT_1, 1n)
      ).to.be.revertedWithCustomError(proxy, "EnforcedPause");
    });

    it("pause blocks craft", async () => {
      await proxy.connect(user).buyCurrency(200n, { value: 200n * CURRENCY_PRICE });
      await proxy.connect(user).buyMaterial(MAT_1, 2n);
      await proxy.connect(user).buyMaterial(MAT_2, 1n);
      await proxy.pause();
      await expect(proxy.connect(user).craft()).to.be.revertedWithCustomError(
        proxy,
        "EnforcedPause"
      );
    });

    it("pause blocks withdraw", async () => {
      await proxy.connect(user).buyCurrency(1n, { value: CURRENCY_PRICE });
      await proxy.pause();
      await expect(
        proxy.connect(admin).withdraw(admin.address, CURRENCY_PRICE)
      ).to.be.revertedWithCustomError(proxy, "EnforcedPause");
    });

    it("non-pauser cannot pause", async () => {
      await expect(proxy.connect(user).pause()).to.be.reverted;
    });

    it("operations resume after unpause", async () => {
      await proxy.pause();
      await proxy.unpause();
      await proxy.connect(user).buyCurrency(1n, { value: CURRENCY_PRICE });
      expect(await proxy.balanceOf(user.address, CURRENCY_ID)).to.equal(1n);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  Upgrade to V2 — state persistence + new features (Transparent Proxy)
  // ───────────────────────────────────────────────────────────────────────────
  describe("V2 Upgrade — state persistence & new features", () => {
    let v2, userCurrencyBefore;

    beforeEach(async () => {
      await proxy.connect(user).buyCurrency(500n, { value: 500n * CURRENCY_PRICE });
      await proxy.connect(user).buyMaterial(MAT_1, 2n);
      await proxy.connect(user).buyMaterial(MAT_2, 1n);
      userCurrencyBefore = await proxy.balanceOf(user.address, CURRENCY_ID);

      // Upgrade to V2 via Transparent Proxy (ProxyAdmin handles authorization)
      const GameEconomyV2 = await ethers.getContractFactory("GameEconomyV2");
      v2 = await upgrades.upgradeProxy(await proxy.getAddress(), GameEconomyV2, { kind: "transparent" });
      await v2.waitForDeployment();
    });

    it("preserves currency balance after upgrade", async () => {
      expect(await v2.balanceOf(user.address, CURRENCY_ID)).to.equal(userCurrencyBefore);
    });

    it("preserves material balances after upgrade", async () => {
      expect(await v2.balanceOf(user.address, MAT_1)).to.equal(2n);
      expect(await v2.balanceOf(user.address, MAT_2)).to.equal(1n);
    });

    it("preserves material prices after upgrade", async () => {
      expect(await v2.materialPrice(MAT_1)).to.equal(10n);
      expect(await v2.materialPrice(MAT_2)).to.equal(20n);
      expect(await v2.materialPrice(MAT_3)).to.equal(5n);
    });

    it("preserves recipe after upgrade", async () => {
      expect(await v2.recipe(MAT_1)).to.equal(2n);
      expect(await v2.recipe(MAT_2)).to.equal(1n);
    });

    it("preserves nextUniqueId after upgrade", async () => {
      expect(await v2.nextUniqueId()).to.equal(1000n);
    });

    it("version() returns 'V2'", async () => {
      expect(await v2.version()).to.equal("V2");
    });

    it("V2: buyMaterialsBatch purchases multiple materials with single currency burn", async () => {
      const ids     = [MAT_1, MAT_3];
      const amounts = [3n, 2n];
      const expectedCost = 3n * 10n + 2n * 5n; // 40

      const currencyBefore = await v2.balanceOf(user.address, CURRENCY_ID);
      await v2.connect(user).buyMaterialsBatch(ids, amounts);

      expect(await v2.balanceOf(user.address, CURRENCY_ID)).to.equal(currencyBefore - expectedCost);
      expect(await v2.balanceOf(user.address, MAT_1)).to.equal(2n + 3n);
      expect(await v2.balanceOf(user.address, MAT_3)).to.equal(2n);
    });

    it("V2: buyMaterialsBatch emits MaterialsBatchPurchased", async () => {
      const ids     = [MAT_1, MAT_3];
      const amounts = [1n, 1n];
      const cost    = 10n + 5n;
      await expect(v2.connect(user).buyMaterialsBatch(ids, amounts))
        .to.emit(v2, "MaterialsBatchPurchased")
        .withArgs(user.address, ids, amounts, cost);
    });

    it("V2: buyMaterialsBatch reverts on insufficient currency", async () => {
      const huge = [MAT_2];
      const hugeAmt = [99999n];
      await expect(
        v2.connect(user).buyMaterialsBatch(huge, hugeAmt)
      ).to.be.revertedWith("GameEconomy: insufficient currency");
    });

    it("V2: buyMaterialsBatch reverts on length mismatch", async () => {
      await expect(
        v2.connect(user).buyMaterialsBatch([MAT_1, MAT_2], [1n])
      ).to.be.revertedWith("GameEconomy: length mismatch");
    });

    it("V2: buyMaterialsBatch reverts on empty batch", async () => {
      await expect(
        v2.connect(user).buyMaterialsBatch([], [])
      ).to.be.revertedWith("GameEconomy: empty batch");
    });

    it("V2: crafting still works after upgrade", async () => {
      await v2.connect(user).craft();
      expect(await v2.balanceOf(user.address, 1000n)).to.equal(1n);
    });

    it("V2: pause still blocks buyMaterialsBatch", async () => {
      await v2.pause();
      await expect(
        v2.connect(user).buyMaterialsBatch([MAT_1], [1n])
      ).to.be.revertedWithCustomError(v2, "EnforcedPause");
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  //  End-to-end flow: buy → craft
  // ───────────────────────────────────────────────────────────────────────────
  describe("End-to-end: buy currency → buy materials → craft", () => {
    it("completes full happy path", async () => {
      await proxy.connect(user).buyCurrency(100n, { value: 100n * CURRENCY_PRICE });
      expect(await proxy.balanceOf(user.address, CURRENCY_ID)).to.equal(100n);

      await proxy.connect(user).buyMaterial(MAT_1, 2n);
      await proxy.connect(user).buyMaterial(MAT_2, 1n);
      expect(await proxy.balanceOf(user.address, CURRENCY_ID)).to.equal(60n);

      const nextId = await proxy.nextUniqueId();
      await proxy.connect(user).craft();

      expect(await proxy.balanceOf(user.address, MAT_1)).to.equal(0n);
      expect(await proxy.balanceOf(user.address, MAT_2)).to.equal(0n);
      expect(await proxy.balanceOf(user.address, nextId)).to.equal(1n);
      expect(await proxy.nextUniqueId()).to.equal(nextId + 1n);
    });
  });
});
