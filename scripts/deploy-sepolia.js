const hre = require("hardhat");

async function main() {
  const provider = new hre.ethers.JsonRpcProvider(process.env.RPC_URL);
  const wallet = new hre.ethers.Wallet(process.env.PRIVATE_KEY, provider);

  console.log("=".repeat(60));
  console.log("DEPLOYING TO SEPOLIA TESTNET");
  console.log("=".repeat(60));
  console.log("Deployer:", wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH");
  console.log("=".repeat(60));

  // Helper to deploy a contract
  async function deploy(name, args = []) {
    const factory = await hre.ethers.getContractFactory(name, wallet);
    const deployTx = await factory.getDeployTransaction(...args);
    
    const tx = await wallet.sendTransaction(deployTx);
    console.log("  Tx sent:", tx.hash);
    console.log("  Waiting for confirmation...");
    
    const receipt = await provider.waitForTransaction(tx.hash, 1, 120000);
    if (!receipt || receipt.status === 0) {
      throw new Error(`Deploy of ${name} failed!`);
    }
    
    const addr = receipt.contractAddress;
    console.log("  ✓", name, "deployed at:", addr);
    console.log("  → https://sepolia.etherscan.io/address/" + addr);
    return addr;
  }

  // Helper to send a transaction
  async function sendTx(to, data, description) {
    const tx = await wallet.sendTransaction({ to, data });
    console.log("  Tx:", tx.hash);
    const receipt = await provider.waitForTransaction(tx.hash, 1, 120000);
    if (!receipt || receipt.status === 0) {
      throw new Error(`${description} failed!`);
    }
    console.log("  ✓", description);
    return receipt;
  }

  // 1. Deploy MTN Token
  console.log("\n[1/5] Deploying MetanaToken (MTN)...");
  const mtnAddr = await deploy("MetanaToken");

  // 2. Deploy MTN Staking
  console.log("\n[2/5] Deploying MTNStaking...");
  const stakingAddr = await deploy("MTNStaking", [mtnAddr]);

  // 3. Deploy wMTN
  console.log("\n[3/5] Deploying WrappedMetana (wMTN)...");
  const wMTNAddr = await deploy("WrappedMetana");

  // 4. Deploy DepositContract
  console.log("\n[4/5] Deploying DepositContract...");
  const depositAddr = await deploy("DepositContract", [mtnAddr, stakingAddr, hre.ethers.ZeroAddress]);

  // 5. Deploy AutoCompoundingVault
  console.log("\n[5/5] Deploying AutoCompoundingVault (aMTN)...");
  const vaultAddr = await deploy("AutoCompoundingVault", [wMTNAddr, depositAddr]);

  // 6. Configuration
  console.log("\n[CONFIG] Setting up roles and references...");

  // Get contract interfaces for encoding
  const depositIface = (await hre.ethers.getContractFactory("DepositContract")).interface;
  const wMTNIface = (await hre.ethers.getContractFactory("WrappedMetana")).interface;
  const stakingIface = (await hre.ethers.getContractFactory("MTNStaking")).interface;
  const mtnIface = (await hre.ethers.getContractFactory("MetanaToken")).interface;

  // setWMTN
  await sendTx(depositAddr, depositIface.encodeFunctionData("setWMTN", [wMTNAddr]), "setWMTN on DepositContract");

  // setVault
  await sendTx(depositAddr, depositIface.encodeFunctionData("setVault", [vaultAddr]), "setVault on DepositContract");

  // grantRole MINTER_ROLE
  const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));
  await sendTx(wMTNAddr, wMTNIface.encodeFunctionData("grantRole", [MINTER_ROLE, depositAddr]), "Grant MINTER_ROLE to DepositContract");

  // grantRole BURNER_ROLE
  const BURNER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("BURNER_ROLE"));
  await sendTx(wMTNAddr, wMTNIface.encodeFunctionData("grantRole", [BURNER_ROLE, depositAddr]), "Grant BURNER_ROLE to DepositContract");

  // transferOwnership of staking to deposit
  await sendTx(stakingAddr, stakingIface.encodeFunctionData("transferOwnership", [depositAddr]), "Transfer MTNStaking ownership to DepositContract");

  // 7. Mint 1000 MTN to deployer
  console.log("\n[DEMO] Minting 1000 MTN to deployer...");
  await sendTx(mtnAddr, mtnIface.encodeFunctionData("mint", [wallet.address, hre.ethers.parseEther("1000")]), "Mint 1000 MTN to deployer");

  // Final summary
  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT COMPLETE!");
  console.log("=".repeat(60));
  const summary = {
    network: "sepolia",
    deployer: wallet.address,
    MTN: mtnAddr,
    wMTN: wMTNAddr,
    MTNStaking: stakingAddr,
    DepositContract: depositAddr,
    AutoCompoundingVault: vaultAddr,
  };
  console.log(JSON.stringify(summary, null, 2));
  console.log("\nEtherscan Links:");
  console.log("  MTN:", "https://sepolia.etherscan.io/address/" + mtnAddr);
  console.log("  wMTN:", "https://sepolia.etherscan.io/address/" + wMTNAddr);
  console.log("  MTNStaking:", "https://sepolia.etherscan.io/address/" + stakingAddr);
  console.log("  DepositContract:", "https://sepolia.etherscan.io/address/" + depositAddr);
  console.log("  AutoCompoundingVault:", "https://sepolia.etherscan.io/address/" + vaultAddr);
  console.log("=".repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
