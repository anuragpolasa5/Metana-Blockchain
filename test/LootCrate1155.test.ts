import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { LootCrate1155 } from "../typechain-types";

describe("Part C – LootCrate1155 (ERC-1155)", function () {

  const CRATE_PRICE = ethers.parseEther("0.02");
  const SWORD_ID    = 1n;
  const SHIELD_ID   = 2n;

  // ─── Fixture ──────────────────────────────────────────────────────────────
  async function deployLootCrateFixture() {
    const [admin, minter, pauser, user1, user2] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("LootCrate1155");
    const lootCrate: LootCrate1155 = await Factory.deploy(
      "ipfs://QmLoot/",
      admin.address
    );
    await lootCrate.waitForDeployment();

    // Grant separate minter and pauser roles
    await lootCrate.connect(admin).grantRole(await lootCrate.MINTER_ROLE(), minter.address);
    await lootCrate.connect(admin).grantRole(await lootCrate.PAUSER_ROLE(), pauser.address);

    return { lootCrate, admin, minter, pauser, user1, user2 };
  }

  // ─── C-1 : Deployment / inheritance ──────────────────────────────────────
  describe("Deployment (C-1)", function () {
    it("C-1a: URI returns {baseURI}{id}.json", async function () {
      const { lootCrate } = await loadFixture(deployLootCrateFixture);
      expect(await lootCrate.uri(1)).to.equal("ipfs://QmLoot/1.json");
      expect(await lootCrate.uri(42)).to.equal("ipfs://QmLoot/42.json");
    });

    it("C-1b: roles are granted to admin at construction", async function () {
      const { lootCrate, admin, minter, pauser } = await loadFixture(deployLootCrateFixture);
      expect(await lootCrate.hasRole(await lootCrate.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
      expect(await lootCrate.hasRole(await lootCrate.MINTER_ROLE(),        admin.address)).to.be.true;
      expect(await lootCrate.hasRole(await lootCrate.PAUSER_ROLE(),        admin.address)).to.be.true;
      expect(await lootCrate.hasRole(await lootCrate.MINTER_ROLE(),        minter.address)).to.be.true;
      expect(await lootCrate.hasRole(await lootCrate.PAUSER_ROLE(),        pauser.address)).to.be.true;
    });

    it("C-1c: supports ERC-1155 and AccessControl interfaces", async function () {
      const { lootCrate } = await loadFixture(deployLootCrateFixture);
      expect(await lootCrate.supportsInterface("0xd9b67a26")).to.be.true; // ERC-1155
      expect(await lootCrate.supportsInterface("0x7965db0b")).to.be.true; // AccessControl
    });
  });

  // ─── C-2/C-3 : openCrate ─────────────────────────────────────────────────
  describe("openCrate (C-2, C-3) [required]", function () {
    it("C-3a: openCrate reverts with InsufficientPayment when ETH is wrong [required]", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);

      // No ETH sent
      await expect(
        lootCrate.connect(user1).openCrate(1, { value: 0n })
      ).to.be.revertedWithCustomError(lootCrate, "InsufficientPayment");

      // Too little ETH (buying 2 crates but only paying for 1)
      await expect(
        lootCrate.connect(user1).openCrate(2, { value: CRATE_PRICE })
      ).to.be.revertedWithCustomError(lootCrate, "InsufficientPayment");
    });

    it("C-3b: openCrate reverts with ZeroCrateCount for count = 0", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      await expect(
        lootCrate.connect(user1).openCrate(0, { value: 0n })
      ).to.be.revertedWithCustomError(lootCrate, "ZeroCrateCount");
    });

    it("C-3c: openCrate(1) succeeds with exact payment and mints items", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);

      await expect(
        lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE })
      ).to.emit(lootCrate, "CrateOpened");

      // User should have received at least one item (sword, shield, or cosmetic)
      const swords    = await lootCrate.balanceOf(user1.address, SWORD_ID);
      const shields   = await lootCrate.balanceOf(user1.address, SHIELD_ID);
      const cosmetic  = await lootCrate.balanceOf(user1.address, 3n); // first cosmetic id
      const totalItems = swords + shields + cosmetic;
      expect(totalItems).to.be.gte(1n);
    });

    it("C-3d: openCrate(1) with overpayment reverts with InsufficientPayment", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      // Pay 3× the required price — should revert now that we require exact payment
      await expect(
        lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE * 3n })
      ).to.be.revertedWithCustomError(lootCrate, "InsufficientPayment");
    });

    it("C-3e: openCrate(5) with correct payment mints exactly 5 total items", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      const count = 5;
      const tx = await lootCrate.connect(user1).openCrate(count, { value: CRATE_PRICE * BigInt(count) });
      const receipt = await tx.wait();

      // Parse the CrateOpened event to get the actual minted ids/amounts
      const crateEvent = receipt!.logs
        .map((log) => { try { return lootCrate.interface.parseLog(log); } catch { return null; } })
        .find((e) => e?.name === "CrateOpened");
      expect(crateEvent).to.not.be.null;

      // The total number of minted items (sum of amounts) must equal count
      const amounts: bigint[] = crateEvent!.args.amounts;
      const totalMinted = amounts.reduce((acc, a) => acc + a, 0n);
      expect(totalMinted).to.equal(BigInt(count));

      // totalMinted tracking must be consistent with what was actually minted
      const swordsMinted  = await lootCrate.totalMinted(SWORD_ID);
      const shieldsMinted = await lootCrate.totalMinted(SHIELD_ID);
      expect(swordsMinted + shieldsMinted).to.be.lte(BigInt(count)); // fungibles <= count
    });

    it("C-2a: cosmetic NFT receives ID >= 3", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      // Open many crates to increase chance of a cosmetic drop
      const count = 20;
      await lootCrate.connect(user1).openCrate(count, { value: CRATE_PRICE * BigInt(count) });

      // The next cosmetic ID would start at 3 and increment; check nothing <= 2 for cosmetics
      // Swords/shields are IDs 1 and 2; any CosmeticMinted event must have id >= 3
      // We verify by checking that if any cosmetic was minted it has id >= 3
      const filter = lootCrate.filters.CosmeticMinted(user1.address, null);
      const events = await lootCrate.queryFilter(filter);
      for (const e of events) {
        expect(e.args.tokenId).to.be.gte(3n);
      }
    });
  });

  // ─── C-4 : mintBatch airdrop ──────────────────────────────────────────────
  describe("mintBatch airdrop (C-4)", function () {
    it("C-4a: MINTER_ROLE can airdrop sword and shield batches", async function () {
      const { lootCrate, minter, user1 } = await loadFixture(deployLootCrateFixture);

      const ids     = [SWORD_ID, SHIELD_ID];
      const amounts = [10n, 5n];

      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, ids, amounts)
      ).to.emit(lootCrate, "TransferBatch");

      expect(await lootCrate.balanceOf(user1.address, SWORD_ID)).to.equal(10n);
      expect(await lootCrate.balanceOf(user1.address, SHIELD_ID)).to.equal(5n);
    });

    it("C-4b: non-MINTER cannot airdrop", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      // OZ 4.x AccessControl reverts with a string message
      await expect(
        lootCrate.connect(user1).mintBatch(user1.address, [SWORD_ID], [1n])
      ).to.be.revertedWith(/AccessControl/);
    });

    it("C-4c: mintBatch enforces supply cap for fungible IDs", async function () {
      const { lootCrate, minter, user1 } = await loadFixture(deployLootCrateFixture);
      const MAX = 5000n;

      // Airdrop exactly MAX swords — should succeed
      await lootCrate.connect(minter).mintBatch(user1.address, [SWORD_ID], [MAX]);
      expect(await lootCrate.totalMinted(SWORD_ID)).to.equal(MAX);

      // One more should revert with SupplyCapExceeded
      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, [SWORD_ID], [1n])
      ).to.be.revertedWithCustomError(lootCrate, "SupplyCapExceeded");
    });

    it("C-4d: MINTER_ROLE can airdrop a cosmetic (ID >= 3) with amount == 1", async function () {
      const { lootCrate, minter, user1 } = await loadFixture(deployLootCrateFixture);
      const cosmeticId = 3n;

      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, [cosmeticId], [1n])
      )
        .to.emit(lootCrate, "TransferBatch")
        .and.to.emit(lootCrate, "CosmeticMinted")
        .withArgs(user1.address, cosmeticId);

      expect(await lootCrate.balanceOf(user1.address, cosmeticId)).to.equal(1n);
      expect(await lootCrate.totalMinted(cosmeticId)).to.equal(1n);
    });

    it("C-4e: mintBatch reverts with CosmeticDuplicateMint when re-minting a cosmetic ID", async function () {
      const { lootCrate, minter, user1, user2 } = await loadFixture(deployLootCrateFixture);
      const cosmeticId = 3n;

      // First mint succeeds
      await lootCrate.connect(minter).mintBatch(user1.address, [cosmeticId], [1n]);

      // Second mint of the same cosmetic ID must revert
      await expect(
        lootCrate.connect(minter).mintBatch(user2.address, [cosmeticId], [1n])
      ).to.be.revertedWithCustomError(lootCrate, "CosmeticDuplicateMint");
    });

    it("C-4f: mintBatch reverts with CosmeticAmountNotOne when cosmetic amount != 1", async function () {
      const { lootCrate, minter, user1 } = await loadFixture(deployLootCrateFixture);
      const cosmeticId = 5n;

      // amount = 2 should revert
      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, [cosmeticId], [2n])
      ).to.be.revertedWithCustomError(lootCrate, "CosmeticAmountNotOne");

      // amount = 0 should revert
      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, [cosmeticId], [0n])
      ).to.be.revertedWithCustomError(lootCrate, "CosmeticAmountNotOne");
    });

    it("C-4g: airdropping cosmetic ID advances _nextCosmeticId to prevent openCrate collision", async function () {
      const { lootCrate, minter, user1 } = await loadFixture(deployLootCrateFixture);

      // Airdrop cosmetic ID 10 (skipping ahead of the default _nextCosmeticId = 3)
      const skippedAheadId = 10n;
      await lootCrate.connect(minter).mintBatch(user1.address, [skippedAheadId], [1n]);

      // Now open enough crates to trigger at least one cosmetic roll (10 % probability).
      // We need to verify that openCrate never re-issues ID 10 (or any <= 10).
      // Run 30 crates to get a high statistical chance of at least one cosmetic.
      const count = 30;
      const tx = await lootCrate.connect(user1).openCrate(count, { value: ethers.parseEther("0.02") * BigInt(count) });
      const receipt = await tx.wait();

      const cosmeticEvents = receipt!.logs
        .map((log) => { try { return lootCrate.interface.parseLog(log); } catch { return null; } })
        .filter((e) => e?.name === "CosmeticMinted");

      // Any cosmetics minted by openCrate must have IDs strictly > 10 (i.e. >= 11)
      for (const e of cosmeticEvents) {
        expect(e!.args.tokenId).to.be.gt(skippedAheadId);
      }
    });
  });

  // ─── C-5 : pause / unpause ────────────────────────────────────────────────
  describe("pause / unpause (C-5) [required]", function () {
    it("C-5a: pause blocks openCrate [required]", async function () {
      const { lootCrate, pauser, user1 } = await loadFixture(deployLootCrateFixture);

      await expect(lootCrate.connect(pauser).pause())
        .to.emit(lootCrate, "Paused")
        .withArgs(pauser.address);

      // openCrate must revert while paused
      await expect(
        lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE })
      ).to.be.revertedWith("Pausable: paused");
    });

    it("C-5b: unpause re-enables openCrate", async function () {
      const { lootCrate, pauser, user1 } = await loadFixture(deployLootCrateFixture);

      await lootCrate.connect(pauser).pause();
      await expect(lootCrate.connect(pauser).unpause())
        .to.emit(lootCrate, "Unpaused")
        .withArgs(pauser.address);

      // Should work again
      await expect(
        lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE })
      ).to.emit(lootCrate, "CrateOpened");
    });

    it("C-5c: non-PAUSER cannot pause", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      // OZ 4.x AccessControl reverts with a string message
      await expect(lootCrate.connect(user1).pause())
        .to.be.revertedWith(/AccessControl/);
    });

    it("C-5d: pause blocks openCrate (mintBatch has no whenNotPaused guard by spec)", async function () {
      const { lootCrate, pauser, minter, user1 } = await loadFixture(deployLootCrateFixture);
      await lootCrate.connect(pauser).pause();
      // openCrate is gated with whenNotPaused — must revert
      await expect(
        lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE })
      ).to.be.revertedWith("Pausable: paused");
      // mintBatch intentionally has no whenNotPaused (MINTER_ROLE airdrops are not halted)
      await expect(
        lootCrate.connect(minter).mintBatch(user1.address, [SWORD_ID], [1n])
      ).to.emit(lootCrate, "TransferBatch");
    });
  });

  // ─── URI management ───────────────────────────────────────────────────────
  describe("URI management", function () {
    it("admin can update base URI", async function () {
      const { lootCrate, admin } = await loadFixture(deployLootCrateFixture);
      await lootCrate.connect(admin).setBaseURI("ipfs://NewLoot/");
      expect(await lootCrate.uri(1)).to.equal("ipfs://NewLoot/1.json");
    });

    it("non-admin cannot update base URI", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);
      // OZ 4.x AccessControl reverts with a string message
      await expect(lootCrate.connect(user1).setBaseURI("bad"))
        .to.be.revertedWith(/AccessControl/);
    });
  });

  // ─── Withdrawal ───────────────────────────────────────────────────────────
  describe("ETH withdrawal", function () {
    it("admin can withdraw ETH collected from crate sales", async function () {
      const { lootCrate, admin, user1 } = await loadFixture(deployLootCrateFixture);

      // Buy 3 crates to accumulate ETH in contract
      const count = 3;
      await lootCrate.connect(user1).openCrate(count, { value: CRATE_PRICE * BigInt(count) });

      const contractBal = await ethers.provider.getBalance(await lootCrate.getAddress());
      expect(contractBal).to.equal(CRATE_PRICE * BigInt(count));

      const adminBalBefore = await ethers.provider.getBalance(admin.address);
      const tx = await lootCrate.connect(admin).withdraw();
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const adminBalAfter = await ethers.provider.getBalance(admin.address);
      expect(adminBalAfter).to.be.closeTo(
        adminBalBefore + contractBal - gasUsed,
        ethers.parseEther("0.0001") // 0.01 % tolerance
      );
    });
  });

  // ─── Exhausted fungible supply (covers line 202) ──────────────────────────
  describe("Exhausted fungible supply – skipped-roll refund (line 202)", function () {
    it("C-6a: skipped rolls are refunded when BOTH fungible caps are exhausted", async function () {
      const { lootCrate, admin, minter, user1 } = await loadFixture(deployLootCrateFixture);
      const MAX = 5000n;

      // Exhaust both sword and shield supply via airdrop
      await lootCrate.connect(minter).mintBatch(user1.address, [SWORD_ID], [MAX]);
      await lootCrate.connect(minter).mintBatch(user1.address, [SHIELD_ID], [MAX]);

      expect(await lootCrate.totalMinted(SWORD_ID)).to.equal(MAX);
      expect(await lootCrate.totalMinted(SHIELD_ID)).to.equal(MAX);

      // Open a batch of crates. With both fungible supplies exhausted only cosmetics
      // can be minted (10 % chance); all non-cosmetic rolls are skipped and refunded.
      const crateCount = 10;
      const totalCost  = CRATE_PRICE * BigInt(crateCount);

      const balBefore = await ethers.provider.getBalance(user1.address);
      const tx     = await lootCrate.connect(user1).openCrate(crateCount, { value: totalCost });
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
      const balAfter = await ethers.provider.getBalance(user1.address);

      // Parse all events from the transaction
      const allEvents = receipt!.logs
        .map((log) => { try { return lootCrate.interface.parseLog(log); } catch { return null; } })
        .filter(Boolean);

      const refundEvent = allEvents.find((e) => e?.name === "SkippedRollRefund");

      // If no cosmetics happened to drop on any of the 10 crates (very rare but possible),
      // all 10 rolls were skipped and we expect the full refund.
      // More commonly, some cosmetics land and the rest are refunded.
      if (refundEvent) {
        const skippedCount  = refundEvent!.args.skippedCount as bigint;
        const refundAmount  = refundEvent!.args.refundAmount  as bigint;

        expect(skippedCount).to.be.gte(1n);
        expect(refundAmount).to.equal(CRATE_PRICE * skippedCount);

        // User's net ETH cost = totalCost - refund + gas ≈ CRATE_PRICE * (crateCount - skipped)
        const netCost = totalCost - refundAmount + gasUsed;
        expect(balBefore - balAfter).to.be.closeTo(netCost, ethers.parseEther("0.0001"));
      } else {
        // All 10 were cosmetics — no skipped rolls, full amount deducted minus gas only
        expect(balBefore - balAfter).to.be.closeTo(totalCost + gasUsed, ethers.parseEther("0.0001"));
      }
    });

    it("C-6b: no refund event when fungible supply is NOT exhausted", async function () {
      const { lootCrate, user1 } = await loadFixture(deployLootCrateFixture);

      // Fresh contract — no caps exhausted yet
      const tx     = await lootCrate.connect(user1).openCrate(1, { value: CRATE_PRICE });
      const receipt = await tx.wait();

      const refundEvent = receipt!.logs
        .map((log) => { try { return lootCrate.interface.parseLog(log); } catch { return null; } })
        .find((e) => e?.name === "SkippedRollRefund");

      // There should be no SkippedRollRefund when supply is available
      expect(refundEvent).to.be.undefined;
    });
  });
});