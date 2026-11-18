import { Wallet } from "zksync-ethers";
import { Deployer } from "@matterlabs/hardhat-zksync";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import dotenv from "dotenv";

dotenv.config();

/**
 * Deployment script for MyToken on zkSync Era.
 *
 * L2-3: Passes the token name ("MyToken") and symbol ("MTK") as constructor arguments.
 * L2-4: Deploys and verifies the contract on zkSync Sepolia.
 */
export default async function (hre: HardhatRuntimeEnvironment) {
  // Load the deployer wallet from the private key in .env
  const wallet = new Wallet(process.env.PRIVATE_KEY!);
  const deployer = new Deployer(hre, wallet);

  // Load the artifact for MyToken
  const artifact = await deployer.loadArtifact("MyToken");

  // L2-3: Pass name and symbol as constructor arguments
  const tokenName = "MyToken";
  const tokenSymbol = "MTK";

  console.log(`Deploying ${tokenName} (${tokenSymbol}) on zkSync Era...`);

  const contract = await deployer.deploy(artifact, [tokenName, tokenSymbol]);
  const contractAddress = await contract.getAddress();

  console.log(`\n--- Deployment Successful ---`);
  console.log(`Token Name: ${tokenName}`);
  console.log(`Token Symbol: ${tokenSymbol}`);
  console.log(`Contract Address: ${contractAddress}`);
  console.log(`Explorer: https://sepolia-era.zksync.network/address/${contractAddress}`);
  console.log(`\nVerifying contract...`);

  // L2-4: Verify the contract on zkSync Sepolia explorer
  try {
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: [tokenName, tokenSymbol],
    });
    console.log(`Contract verified successfully!`);
    console.log(`Verified at: https://sepolia-era.zksync.network/address/${contractAddress}#code`);
  } catch (error: any) {
    if (error.message.includes("already verified")) {
      console.log(`Contract already verified.`);
    } else {
      console.log(`Verification failed: ${error.message}`);
      console.log(`You can manually verify later.`);
    }
  }
}
