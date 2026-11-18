import { HardhatUserConfig } from "hardhat/config";
import "@matterlabs/hardhat-zksync";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  defaultNetwork: "zkSyncSepolia",
  networks: {
    zkSyncSepolia: {
      url: process.env.RPC_URL || "https://sepolia.era.zksync.dev",
      ethNetwork: "sepolia",
      zksync: true,
      verifyURL: "https://explorer.sepolia.era.zksync.dev/contract_verification",
    },
    zkSyncMainnet: {
      url: "https://mainnet.era.zksync.io",
      ethNetwork: "mainnet",
      zksync: true,
      verifyURL: "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
  },
  solidity: {
    version: "0.8.24",
  },
  zksolc: {
    version: "1.5.7",
  },
};

export default config;
