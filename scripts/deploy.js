const { ethers } = require("hardhat");

// Workaround for yParity mismatch error with some RPCs
async function deployContract(factory, args = []) {
  const contract = await factory.deploy(...args);
  const deployTx = contract.deploymentTransaction();
  if (deployTx) {
    // Wait for the transaction to be mined using provider
    const receipt = await ethers.provider.waitForTransaction(deployTx.hash, 1);
    if (!receipt || receipt.status === 0) {
      throw new Error(`Deployment failed. Tx: ${deployTx.hash}`);
    }
  }
  return contract;
}

async function waitForTx(tx) {
  const receipt = await ethers.provider.waitForTransaction(tx.hash, 1);
  if (!receipt || receipt.status === 0) {
    throw new Error(`Transaction failed. Tx: ${tx.hash}`);
  }
  return receipt;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const balance = await ethers.provider.getBalance(deployer.address);

  console.log("=".repeat(60));
  console.log("DEPLOYING TO SEPOLIA TESTNET");
  console.log("=".repeat(60));
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // 1. Deploy MTN Token
  console.log("\n[1/5] Deploying MetanaToken (MTN)...");
  const MetanaToken = await ethers.getContractFactory("MetanaToken");
  const mtn = await deployContract(MetanaToken);
  const mtnAddr = await mtn.getAddress();
  console.log("  ✓ MTN:", mtnAddr);
  console.log("  → https://sepolia.etherscan.io/address/" + mtnAddr);

  // 2. Deploy MTN Staking Contract
  console.log("\n[2/5] Deploying MTNStaking...");
  const MTNStaking = await ethers.getContractFactory("MTNStaking");
  const staking = await deployContract(MTNStaking, [mtnAddr]);
  const stakingAddr = await staking.getAddress();
  console.log("  ✓ MTNStaking:", stakingAddr);
  console.log("  → https://sepolia.etherscan.io/address/" + stakingAddr);

  // 3. Deploy Wrapped Metana (wMTN)
  console.log("\n[3/5] Deploying WrappedMetana (wMTN)...");
  const WrappedMetana = await ethers.getContractFactory("WrappedMetana");
  const wMTN = await deployContract(WrappedMetana);
  const wMTNAddr = await wMTN.getAddress();
  console.log("  ✓ wMTN:", wMTNAddr);
  console.log("  → https://sepolia.etherscan.io/address/" + wMTNAddr);

  // 4. Deploy Deposit Contract
  console.log("\n[4/5] Deploying DepositContract...");
  const DepositContract = await ethers.getContractFactory("DepositContract");
  const deposit = await deployContract(DepositContract, [mtnAddr, stakingAddr, ethers.ZeroAddress]);
  const depositAddr = await deposit.getAddress();
  console.log("  ✓ DepositContract:", depositAddr);
  console.log("  → https://sepolia.etherscan.io/address/" + depositAddr);

  // 5. Deploy AutoCompounding Vault
  console.log("\n[5/5] Deploying AutoCompoundingVault (aMTN)...");
  const AutoCompoundingVault = await ethers.getContractFactory("AutoCompoundingVault");
  const vault = await deployContract(AutoCompoundingVault, [wMTNAddr, depositAddr]);
  const vaultAddr = await vault.getAddress();
  console.log("  ✓ AutoCompoundingVault:", vaultAddr);
  console.log("  → https://sepolia.etherscan.io/address/" + vaultAddr);

  // 6. Configuration transactions
  console.log("\n[CONFIG] Setting up roles and references...");

  let tx;
  tx = await deposit.setWMTN(wMTNAddr);
  await waitForTx(tx);
  console.log("  ✓ wMTN set on DepositContract");

  tx = await deposit.setVault(vaultAddr);
  await waitForTx(tx);
  console.log("  ✓ Vault set on DepositContract");

  const MINTER_ROLE = await wMTN.MINTER_ROLE();
  const BURNER_ROLE = await wMTN.BURNER_ROLE();

  tx = await wMTN.grantRole(MINTER_ROLE, depositAddr);
  await waitForTx(tx);
  console.log("  ✓ MINTER_ROLE granted to DepositContract");

  tx = await wMTN.grantRole(BURNER_ROLE, depositAddr);
  await waitForTx(tx);
  console.log("  ✓ BURNER_ROLE granted to DepositContract");

  tx = await staking.transferOwnership(depositAddr);
  await waitForTx(tx);
  console.log("  ✓ MTNStaking ownership → DepositContract");

  // 7. Mint some MTN to deployer for demo
  console.log("\n[DEMO SETUP] Minting 1000 MTN to deployer...");
  tx = await mtn.mint(deployer.address, ethers.parseEther("1000"));
  await waitForTx(tx);
  console.log("  ✓ 1000 MTN minted to", deployer.address);

  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT COMPLETE");
  console.log("=".repeat(60));
  const addresses = {
    network: "sepolia",
    deployer: deployer.address,
    MTN: mtnAddr,
    wMTN: wMTNAddr,
    MTNStaking: stakingAddr,
    DepositContract: depositAddr,
    AutoCompoundingVault: vaultAddr,
  };
  console.log(JSON.stringify(addresses, null, 2));
  console.log("=".repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
