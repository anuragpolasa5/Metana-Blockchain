import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { VestingToken, VestingVault } from "../typechain-types";

describe("Part A – VestingToken & VestingVault", function () {
  let vestingToken: VestingToken;
  let vestingVault: VestingVault;
  let admin: any;
  let beneficiary: any;
  let other: any;

  const TOKEN_NAME   = "Vesting Token";
  const TOKEN_SYMBOL = "VTK";
  const TOTAL_SUPPLY = ethers.parseUnits("100000000", 18); // 100 M tokens

  // cliff = 30 days, duration = 1 year
  const CLIFF    = 30 * 24 * 3600;
  const DURATION = 365 * 24 * 3600;
  const AMOUNT   = ethers.parseUnits("1000", 18);

  beforeEach(async function () {
    [admin, beneficiary, other] = await ethers.getSigners();

    const VestingTokenFactory = await ethers.getContractFactory("VestingToken");
    vestingToken = await VestingTokenFactory.deploy(TOKEN_NAME, TOKEN_SYMBOL, admin.address);
    await vestingToken.waitForDeployment();

    const VestingVaultFactory = await ethers.getContractFactory("VestingVault");
    vestingVault = await VestingVaultFactory.deploy(
      await vestingToken.getAddress(),
      admin.address
    );
    await vestingVault.waitForDeployment();

    // Grant MINTER_ROLE to the vault so it can mint on claim
    await vestingToken.grantRole(
      await vestingToken.MINTER_ROLE(),
      await vestingVault.getAddress()
    );
  });

  // ─── A-1 : VestingToken ───────────────────────────────────────────────────
  describe("VestingToken (A-1)", function () {
    it("A-1a: has correct name and symbol", async function () {
      expect(await vestingToken.name()).to.equal(TOKEN_NAME);
      expect(await vestingToken.symbol()).to.equal(TOKEN_SYMBOL);
    });

    it("A-1b: mints 100 million tokens to admin at construction", async function () {
      expect(await vestingToken.balanceOf(admin.address)).to.equal(TOTAL_SUPPLY);
    });

    it("A-1c: total supply equals 100 million after construction", async function () {
      expect(await vestingToken.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("A-1d: vault holds MINTER_ROLE after setup", async function () {
      expect(
        await vestingToken.hasRole(
          await vestingToken.MINTER_ROLE(),
          await vestingVault.getAddress()
        )
      ).to.be.true;
    });

    it("A-1e: non-minter cannot mint tokens", async function () {
      // OZ 4.x AccessControl reverts with a string message (not a custom error)
      await expect(vestingToken.connect(other).mint(other.address, 1n))
        .to.be.revertedWith(/AccessControl/);
    });
  });

  // ─── A-2 : VestingVault constructor ──────────────────────────────────────
  describe("VestingVault construction (A-2)", function () {
    it("A-2a: token address is set and immutable", async function () {
      expect(await vestingVault.token()).to.equal(await vestingToken.getAddress());
    });

    it("A-2b: admin holds ADMIN_ROLE", async function () {
      expect(
        await vestingVault.hasRole(await vestingVault.ADMIN_ROLE(), admin.address)
      ).to.be.true;
    });

    // ── Covers VestingVault.sol line 58 ──────────────────────────────────────
    it("A-2c: deploying with EOA token address reverts with InvalidTokenAddress (line 58)", async function () {
      // `other` is a plain EOA — code.length == 0
      const VestingVaultFactory = await ethers.getContractFactory("VestingVault");
      await expect(
        VestingVaultFactory.deploy(other.address, admin.address)
      ).to.be.revertedWithCustomError({ interface: VestingVaultFactory.interface } as any, "InvalidTokenAddress");
    });

    it("A-2d: deploying with address(0) as token address reverts with InvalidTokenAddress", async function () {
      const VestingVaultFactory = await ethers.getContractFactory("VestingVault");
      await expect(
        VestingVaultFactory.deploy(ethers.ZeroAddress, admin.address)
      ).to.be.revertedWithCustomError({ interface: VestingVaultFactory.interface } as any, "InvalidTokenAddress");
    });

    it("A-2e: deploying with address(0) as admin reverts with ZeroAdminAddress", async function () {
      const VestingVaultFactory = await ethers.getContractFactory("VestingVault");
      const tokenAddr = await vestingToken.getAddress();
      await expect(
        VestingVaultFactory.deploy(tokenAddr, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError({ interface: VestingVaultFactory.interface } as any, "ZeroAdminAddress");
    });
  });

  // ─── A-3 : createSchedule ─────────────────────────────────────────────────
  describe("createSchedule (A-3)", function () {
    it("A-3a: non-admin CANNOT create schedules [required]", async function () {
      // OZ 4.x AccessControl reverts with a string message (not a custom error)
      await expect(
        vestingVault.connect(other).createSchedule(beneficiary.address, CLIFF, DURATION, AMOUNT)
      ).to.be.revertedWith(/AccessControl/);
    });

    it("A-3b: admin can create a schedule and emits ScheduleCreated", async function () {
      await expect(
        vestingVault.connect(admin).createSchedule(beneficiary.address, CLIFF, DURATION, AMOUNT)
      )
        .to.emit(vestingVault, "ScheduleCreated")
        .withArgs(0n, beneficiary.address, AMOUNT, CLIFF, DURATION);

      const s = await vestingVault.schedules(0);
      expect(s.beneficiary).to.equal(beneficiary.address);
      expect(s.cliff).to.equal(CLIFF);
      expect(s.duration).to.equal(DURATION);
      expect(s.totalAmount).to.equal(AMOUNT);
      expect(s.claimedAmount).to.equal(0n);
    });

    it("A-3c: nextScheduleId increments after creation", async function () {
      await vestingVault.connect(admin).createSchedule(beneficiary.address, CLIFF, DURATION, AMOUNT);
      await vestingVault.connect(admin).createSchedule(beneficiary.address, CLIFF, DURATION, AMOUNT);
      expect(await vestingVault.nextScheduleId()).to.equal(2n);
    });

    it("A-3d: reverts with InvalidSchedule for zero address beneficiary", async function () {
      await expect(
        vestingVault.connect(admin).createSchedule(ethers.ZeroAddress, CLIFF, DURATION, AMOUNT)
      ).to.be.revertedWithCustomError(vestingVault, "InvalidSchedule");
    });

    it("A-3e: reverts with InvalidSchedule for zero duration", async function () {
      await expect(
        vestingVault.connect(admin).createSchedule(beneficiary.address, CLIFF, 0, AMOUNT)
      ).to.be.revertedWithCustomError(vestingVault, "InvalidSchedule");
    });
  });

  // ─── A-4/A-5 : Schedule releases correct amounts over time ───────────────
  describe("Schedule vesting timeline (A-4) [required]", function () {
    beforeEach(async function () {
      await vestingVault.connect(admin).createSchedule(beneficiary.address, CLIFF, DURATION, AMOUNT);
    });

    it("A-4a: vested = 0 before cliff passes", async function () {
      expect(await vestingVault.vestedAmount(0)).to.equal(0n);
      expect(await vestingVault.claimable(0)).to.equal(0n);
    });

    it("A-4b: nothing claimable immediately at cliff boundary", async function () {
      await time.increase(CLIFF);
      // At the exact cliff end, elapsed = 0 so vested = 0
      expect(await vestingVault.vestedAmount(0)).to.equal(0n);
    });

    it("A-4c: ≈ half of tokens vested at cliff + duration/2 [required]", async function () {
      await time.increase(CLIFF + DURATION / 2);
      const vested   = await vestingVault.vestedAmount(0);
      const expected = AMOUNT / 2n;
      // Allow 0.1 % rounding tolerance
      const tol = expected / 1000n;
      expect(vested).to.be.closeTo(expected, tol);
    });

    it("A-4d: full amount vested after cliff + duration", async function () {
      await time.increase(CLIFF + DURATION + 1);
      expect(await vestingVault.vestedAmount(0)).to.equal(AMOUNT);
    });

    it("A-4e: beneficiary can claim and receives exactly the claimable amount", async function () {
      await time.increase(CLIFF + DURATION / 2);

      const balBefore = await vestingToken.balanceOf(beneficiary.address);
      // Capture the tx and read the Claimed event to get the actual minted amount
      // (avoids a 1-block timing mismatch between claimable() view call and the tx)
      const tx = await vestingVault.connect(beneficiary).claim(0);
      const receipt = await tx.wait();

      // Parse the Claimed event to get the actual amount minted
      const claimedEvent = receipt!.logs
        .map((log) => { try { return vestingVault.interface.parseLog(log); } catch { return null; } })
        .find((e) => e?.name === "Claimed");
      expect(claimedEvent).to.not.be.null;
      const mintedAmt = claimedEvent!.args.amount;
      expect(mintedAmt).to.be.gt(0n);

      const balAfter = await vestingToken.balanceOf(beneficiary.address);
      expect(balAfter - balBefore).to.equal(mintedAmt);
    });

    it("A-4f: double-claim is rejected (NothingToClaim) [required]", async function () {
      // Warp to exactly cliff + duration so the full amount is vested and claimable
      await time.increase(CLIFF + DURATION + 1);
      // First claim — collects everything
      await vestingVault.connect(beneficiary).claim(0);
      // Second claim in same block — nothing left to claim
      await expect(vestingVault.connect(beneficiary).claim(0))
        .to.be.revertedWithCustomError(vestingVault, "NothingToClaim");
    });

    it("A-4g: non-beneficiary cannot claim (Unauthorized)", async function () {
      await time.increase(CLIFF + DURATION);
      await expect(vestingVault.connect(other).claim(0))
        .to.be.revertedWithCustomError(vestingVault, "Unauthorized");
    });

    it("A-4h: claim before cliff reverts with NothingToClaim", async function () {
      await time.increase(CLIFF - 1);
      await expect(vestingVault.connect(beneficiary).claim(0))
        .to.be.revertedWithCustomError(vestingVault, "NothingToClaim");
    });

    it("A-4i: accumulated claimedAmount prevents double-claiming across multiple claims", async function () {
      // First claim at half duration
      await time.increase(CLIFF + DURATION / 2);
      await vestingVault.connect(beneficiary).claim(0);

      // Second claim at full duration – should receive only the remaining half
      await time.increase(DURATION / 2 + 1);
      const balBefore = await vestingToken.balanceOf(beneficiary.address);
      await vestingVault.connect(beneficiary).claim(0);
      const received = (await vestingToken.balanceOf(beneficiary.address)) - balBefore;

      // Should be approximately AMOUNT/2 (second half)
      const tol = AMOUNT / 1000n;
      expect(received).to.be.closeTo(AMOUNT / 2n, tol);
    });
  });
});