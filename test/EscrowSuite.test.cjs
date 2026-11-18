const { expect }        = require("chai");
const { ethers }        = require("hardhat");
const { time }          = require("@nomicfoundation/hardhat-network-helpers");

// ─── helpers ────────────────────────────────────────────────────────────────

/**
 * Produce a depositor signature for the RELEASE message.
 * Mirrors SimpleEscrow._hashRelease():
 *   keccak256("\x19Ethereum Signed Message:\n32" ++ keccak256("RELEASE" ++ escrowAddr ++ amount))
 */
async function signRelease(signer, escrowAddress, amount) {
    const innerHash = ethers.solidityPackedKeccak256(
        ["string", "address", "uint256"],
        ["RELEASE",  escrowAddress,  amount]
    );
    // ethers signMessage hashes with the EIP-191 prefix automatically
    return signer.signMessage(ethers.getBytes(innerHash));
}

// ─── fixtures ───────────────────────────────────────────────────────────────

async function deployFactory() {
    const [owner, feeRecipient, depositor, payee, stranger] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("EscrowFactory");
    const factory = await Factory.deploy(feeRecipient.address);
    await factory.waitForDeployment();

    return { factory, owner, feeRecipient, depositor, payee, stranger };
}

// ─── tests ──────────────────────────────────────────────────────────────────

describe("EscrowFactory – deployment & configuration", function () {
    it("stores feeRecipient and feePercent = 1", async function () {
        const { factory, feeRecipient } = await deployFactory();
        expect(await factory.feeRecipient()).to.equal(feeRecipient.address);
        expect(await factory.FEE_PERCENT()).to.equal(1n);
    });

    it("reverts if feeRecipient is zero address", async function () {
        const Factory = await ethers.getContractFactory("EscrowFactory");
        await expect(Factory.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(
            await ethers.getContractFactory("EscrowFactory"), "ZeroAddress"
        );
    });
});

// ════════════════════════════════════════════════════════════════════════════
// TEST 1 – Deterministic address (F-2 × F-3)
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 1 · Deterministic CREATE2 address", function () {
    it("predictAddress() matches the actually deployed escrow", async function () {
        const { factory, depositor, payee } = await deployFactory();

        const deadline = (await time.latest()) + 3600; // 1 h from now
        const salt     = ethers.id("unique-salt-001");

        // Predict before deploying
        const predicted = await factory.predictAddress(
            depositor.address, payee.address, deadline, salt
        );

        // Deploy
        const tx       = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt  = await tx.wait();

        // Parse the EscrowCreated event
        const iface      = factory.interface;
        const log        = receipt.logs.find(l => {
            try { iface.parseLog(l); return true; } catch { return false; }
        });
        const parsed     = iface.parseLog(log);
        const deployed   = parsed.args.escrowAddress;

        expect(deployed).to.equal(predicted);
        console.log("    ✓ predicted:", predicted);
        console.log("    ✓ deployed :", deployed);
    });

    it("returns different addresses for different salts", async function () {
        const { factory, depositor, payee } = await deployFactory();
        const deadline = (await time.latest()) + 3600;

        const addr1 = await factory.predictAddress(depositor.address, payee.address, deadline, ethers.id("salt-A"));
        const addr2 = await factory.predictAddress(depositor.address, payee.address, deadline, ethers.id("salt-B"));

        expect(addr1).to.not.equal(addr2);
    });
});

// ════════════════════════════════════════════════════════════════════════════
// TEST 2 – Happy-path: fund → signed release → verify balances & 1 % fee
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 2 · Happy-path flow with 1 % fee", function () {
    it("fund → signed release → correct balances and 1 % fee forwarded to factory", async function () {
        const { factory, feeRecipient, depositor, payee } = await deployFactory();

        const deadline    = (await time.latest()) + 7200;
        const salt        = ethers.id("happy-path-salt");
        const depositAmt  = ethers.parseEther("1.0");   // 1 ETH

        // ── 1. Deploy escrow ────────────────────────────────────────────────
        const tx     = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();

        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;

        const escrow = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        // ── 2. Fund ─────────────────────────────────────────────────────────
        await escrow.connect(depositor).fund({ value: depositAmt });
        expect(await escrow.balance()).to.equal(depositAmt);
        expect(await escrow.funded()).to.equal(true);

        // ── 3. Sign release ─────────────────────────────────────────────────
        const sig = await signRelease(depositor, escrowAddr, depositAmt);

        // ── 4. Capture balances before release ──────────────────────────────
        const payeeBalanceBefore   = await ethers.provider.getBalance(payee.address);
        const factoryBalanceBefore = await ethers.provider.getBalance(await factory.getAddress());

        // ── 5. Payee triggers release ────────────────────────────────────────
        const releaseTx      = await escrow.connect(payee).release(depositAmt, sig);
        const releaseReceipt = await releaseTx.wait();

        // ── 6. Assertions ────────────────────────────────────────────────────
        const expectedFee     = depositAmt / 100n;          // 1 %
        const expectedToPayee = depositAmt - expectedFee;   // 99 %

        // Payee received 99 % (accounting for gas)
        const payeeBalanceAfter = await ethers.provider.getBalance(payee.address);
        const gasUsed = releaseReceipt.gasUsed * releaseReceipt.gasPrice;
        expect(payeeBalanceAfter).to.equal(payeeBalanceBefore + expectedToPayee - gasUsed);

        // Factory accumulated 1 %
        const factoryBalanceAfter = await ethers.provider.getBalance(await factory.getAddress());
        expect(factoryBalanceAfter).to.equal(factoryBalanceBefore + expectedFee);
        expect(await factory.accumulatedFees()).to.equal(expectedFee);

        // Escrow is now empty and marked released
        expect(await escrow.balance()).to.equal(0n);
        expect(await escrow.released()).to.equal(true);

        console.log("    deposit  :", ethers.formatEther(depositAmt),   "ETH");
        console.log("    payee got:", ethers.formatEther(expectedToPayee), "ETH (99 %)");
        console.log("    fee      :", ethers.formatEther(expectedFee),   "ETH (1 %)");
    });
});

// ════════════════════════════════════════════════════════════════════════════
// BONUS TEST 3 – Deadline reclaim path
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 3 · Deadline reclaim", function () {
    it("depositor can reclaim funds after deadline passes", async function () {
        const { factory, depositor, payee } = await deployFactory();

        const deadline   = (await time.latest()) + 60; // 60 s
        const salt       = ethers.id("reclaim-salt");
        const depositAmt = ethers.parseEther("0.5");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });

        // Travel past deadline
        await time.increase(61);

        const balBefore = await ethers.provider.getBalance(depositor.address);
        const reclaimTx = await escrow.connect(depositor).reclaim();
        const rr        = await reclaimTx.wait();
        const gas       = rr.gasUsed * rr.gasPrice;

        const balAfter = await ethers.provider.getBalance(depositor.address);
        expect(balAfter).to.equal(balBefore + depositAmt - gas);
        expect(await escrow.balance()).to.equal(0n);
    });

    it("depositor cannot reclaim before deadline", async function () {
        const { factory, depositor, payee } = await deployFactory();

        const deadline   = (await time.latest()) + 9999;
        const salt       = ethers.id("reclaim-early-salt");
        const depositAmt = ethers.parseEther("0.1");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });

        await expect(escrow.connect(depositor).reclaim())
            .to.be.revertedWithCustomError(escrow, "DeadlineNotPassed");
    });
});

// ════════════════════════════════════════════════════════════════════════════
// BONUS TEST 4 – Bad signature rejection
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 4 · Signature security", function () {
    it("rejects a signature from the wrong signer", async function () {
        const { factory, depositor, payee, stranger } = await deployFactory();

        const deadline   = (await time.latest()) + 3600;
        const salt       = ethers.id("badsig-salt");
        const depositAmt = ethers.parseEther("0.2");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });

        // Stranger signs instead of depositor
        const badSig = await signRelease(stranger, escrowAddr, depositAmt);

        await expect(escrow.connect(payee).release(depositAmt, badSig))
            .to.be.revertedWithCustomError(escrow, "InvalidSignature");
    });

    it("rejects release with wrong amount in signature", async function () {
        const { factory, depositor, payee } = await deployFactory();

        const deadline   = (await time.latest()) + 3600;
        const salt       = ethers.id("wrongamt-salt");
        const depositAmt = ethers.parseEther("0.3");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });

        // Sign for wrong amount
        const wrongSig = await signRelease(depositor, escrowAddr, ethers.parseEther("0.1"));

        await expect(escrow.connect(payee).release(depositAmt, wrongSig))
            .to.be.revertedWithCustomError(escrow, "InvalidSignature");
    });
});

// ════════════════════════════════════════════════════════════════════════════
// BONUS TEST 5 – Pause logic (F-5)
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 5 · Pause / unpause", function () {
    it("blocks createEscrow when paused, resumes when unpaused", async function () {
        const { factory, owner, depositor, payee } = await deployFactory();

        const deadline = (await time.latest()) + 3600;
        const salt     = ethers.id("pause-salt");

        // Owner pauses
        await factory.connect(owner).pause();

        await expect(
            factory.createEscrow(depositor.address, payee.address, deadline, salt)
        ).to.be.revertedWithCustomError(factory, "EnforcedPause");

        // Owner unpauses
        await factory.connect(owner).unpause();

        await expect(
            factory.createEscrow(depositor.address, payee.address, deadline, salt)
        ).to.not.be.reverted;
    });

    it("only owner can pause", async function () {
        const { factory, stranger } = await deployFactory();
        await expect(factory.connect(stranger).pause())
            .to.be.revertedWithCustomError(factory, "OwnableUnauthorizedAccount");
    });
});

// ════════════════════════════════════════════════════════════════════════════
// BONUS TEST 6 – Fee withdrawal (F-6)
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 6 · Fee withdrawal", function () {
    it("owner can withdraw accumulated fees to feeRecipient", async function () {
        const { factory, owner, feeRecipient, depositor, payee } = await deployFactory();

        const deadline   = (await time.latest()) + 3600;
        const salt       = ethers.id("fee-withdrawal-salt");
        const depositAmt = ethers.parseEther("1.0");

        // Full happy path to accumulate a fee
        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });
        const sig = await signRelease(depositor, escrowAddr, depositAmt);
        await escrow.connect(payee).release(depositAmt, sig);

        const expectedFee = depositAmt / 100n;
        expect(await factory.accumulatedFees()).to.equal(expectedFee);

        // Withdraw fees
        const recipientBefore = await ethers.provider.getBalance(feeRecipient.address);
        await factory.connect(owner).withdrawFees();

        expect(await factory.accumulatedFees()).to.equal(0n);
        const recipientAfter = await ethers.provider.getBalance(feeRecipient.address);
        expect(recipientAfter).to.equal(recipientBefore + expectedFee);
    });

    it("reverts if there are no fees to withdraw", async function () {
        const { factory, owner } = await deployFactory();
        await expect(factory.connect(owner).withdrawFees())
            .to.be.revertedWithCustomError(factory, "NoFeesToWithdraw");
    });
});

// ════════════════════════════════════════════════════════════════════════════
// BONUS TEST 7 – Re-entrancy & double-fund guards
// ════════════════════════════════════════════════════════════════════════════
describe("TEST 7 · Guard rails", function () {
    it("prevents funding twice", async function () {
        const { factory, depositor, payee } = await deployFactory();

        const deadline   = (await time.latest()) + 3600;
        const salt       = ethers.id("double-fund-salt");
        const depositAmt = ethers.parseEther("0.1");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await escrow.connect(depositor).fund({ value: depositAmt });
        await expect(escrow.connect(depositor).fund({ value: depositAmt }))
            .to.be.revertedWithCustomError(escrow, "AlreadyFunded");
    });

    it("only depositor can fund", async function () {
        const { factory, depositor, payee, stranger } = await deployFactory();

        const deadline   = (await time.latest()) + 3600;
        const salt       = ethers.id("stranger-fund-salt");
        const depositAmt = ethers.parseEther("0.1");

        const tx      = await factory.createEscrow(depositor.address, payee.address, deadline, salt);
        const receipt = await tx.wait();
        const iface   = factory.interface;
        const log     = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
        const escrowAddr = iface.parseLog(log).args.escrowAddress;
        const escrow  = await ethers.getContractAt("SimpleEscrow", escrowAddr);

        await expect(escrow.connect(stranger).fund({ value: depositAmt }))
            .to.be.revertedWithCustomError(escrow, "OnlyDepositor");
    });

    it("getEscrows tracks multiple escrows per depositor", async function () {
        const { factory, depositor, payee } = await deployFactory();
        const deadline = (await time.latest()) + 3600;

        await factory.createEscrow(depositor.address, payee.address, deadline, ethers.id("t-1"));
        await factory.createEscrow(depositor.address, payee.address, deadline + 1, ethers.id("t-2"));
        await factory.createEscrow(depositor.address, payee.address, deadline + 2, ethers.id("t-3"));

        const list = await factory.getEscrows(depositor.address);
        expect(list.length).to.equal(3);
    });
});
