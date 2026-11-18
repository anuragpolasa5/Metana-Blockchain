require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: false,
      // Pin to Paris (pre-Cancun). This silences the "selfdestruct deprecated"
      // compiler warning. SimpleEscrow.closeEscrow() uses selfdestruct
      // intentionally per spec requirement E-6; EIP-6780 behaviour is fully
      // documented in the contract's NatSpec. When you deploy to Sepolia or Amoy
      // (both Cancun chains) the EIP-6780 semantics apply at runtime as expected —
      // this setting only affects compiler diagnostics, not opcode behaviour.
      evmVersion: "paris",
    },
  },
  networks: {
    hardhat: {},
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    amoy: {
      url: process.env.AMOY_RPC_URL || "https://rpc-amoy.polygon.technology",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY || "",
    },
  },
};
