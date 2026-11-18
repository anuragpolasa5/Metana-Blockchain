const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying with:", deployer.address);
    console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

    // Use deployer as feeRecipient for demo — change in production
    const feeRecipient = deployer.address;

    const Factory = await ethers.getContractFactory("EscrowFactory");
    const factory = await Factory.deploy(feeRecipient);
    await factory.waitForDeployment();

    const factoryAddr = await factory.getAddress();
    console.log("EscrowFactory deployed to:", factoryAddr);
    console.log("FEE_PERCENT            :", await factory.FEE_PERCENT(), "%");
    console.log("feeRecipient           :", await factory.feeRecipient());

    // ── Demo: spin up one escrow ──────────────────────────────────────────────
    const signers = await ethers.getSigners();
    const depositor = signers[0].address;
    const payee     = signers[1]?.address ?? depositor;
    const deadline  = Math.floor(Date.now() / 1000) + 86400; // 24 h
    const salt      = ethers.id("demo-escrow-001");

    const predicted = await factory.predictAddress(depositor, payee, deadline, salt);
    console.log("\nPredicted escrow address:", predicted);

    const tx      = await factory.createEscrow(depositor, payee, deadline, salt);
    const receipt = await tx.wait();

    const iface = factory.interface;
    const log   = receipt.logs.find(l => { try { iface.parseLog(l); return true; } catch { return false; } });
    const actual = iface.parseLog(log).args.escrowAddress;
    console.log("Actual escrow address   :", actual);
    console.log("Addresses match         :", predicted === actual ? "✓ YES" : "✗ NO");
}

main().catch(err => { console.error(err); process.exit(1); });
