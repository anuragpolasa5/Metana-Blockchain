# Requirements Document

## Introduction

This document defines the requirements for a structured execution plan to deploy three Layer 2 projects: an ERC-20 token on zkSync Era Sepolia, a Cairo simple storage contract on Starknet Sepolia, and a LayerZero OApp cross-chain messenger on Optimism Sepolia and Arbitrum Sepolia. The plan covers prerequisites installation, wallet configuration, deployment execution, and documentation of results.

## Glossary

- **Execution_Plan**: The structured step-by-step deployment guide covering all three parts (A, B, C) of the L2 module
- **Part_A**: The zkSync Era Sepolia ERC-20 token deployment project located in `partA-zksync-erc20/`
- **Part_B**: The Cairo simple storage contract deployment project located in `partB-cairo-storage/`
- **Part_C**: The LayerZero OApp cross-chain messaging project located in `partC-layerzero-oapp/`
- **Deployer**: The user executing the deployment plan
- **Toolchain**: The set of CLI tools required for building and deploying contracts (Node.js, Foundry, Scarb, starkli, snforge)
- **Testnet_ETH**: Native tokens on test networks required to pay gas fees for transactions
- **Peer_Configuration**: The process of registering contract addresses on each chain so LayerZero can route messages between them
- **Cross_Chain_Message**: A message sent from one L2 network to another via the LayerZero protocol
- **Deployment_Record**: The collection of contract addresses, transaction hashes, and explorer links produced during deployment

## Requirements

### Requirement 1: Toolchain Installation

**User Story:** As a Deployer, I want a clear list of all required tools and their installation commands, so that I can set up my development environment before starting deployments.

#### Acceptance Criteria

1. THE Execution_Plan SHALL specify Node.js version 18 or higher as a prerequisite with installation instructions
2. THE Execution_Plan SHALL specify Foundry (forge, cast, anvil) installation via the official foundryup installer, requiring a version that supports Solidity compiler 0.8.24
3. THE Execution_Plan SHALL specify Scarb installation with a version compatible with Cairo edition 2024_07 and starknet dependency 2.9.2
4. THE Execution_Plan SHALL specify starkli installation from the official GitHub repository with a version that supports Starknet Sepolia network interactions
5. THE Execution_Plan SHALL specify snforge installation from starknet-foundry version 0.34.0
6. WHEN a tool is already installed, THE Execution_Plan SHALL provide a version check command for each tool that outputs the installed version number, enabling the Deployer to confirm the version meets or exceeds the minimum specified in criteria 1 through 5
7. IF a version check command reports a version below the minimum specified for that tool, THEN THE Execution_Plan SHALL instruct the Deployer to upgrade to the required version before proceeding

### Requirement 2: Wallet Setup and Testnet ETH Acquisition

**User Story:** As a Deployer, I want instructions for configuring wallets and obtaining testnet ETH on all required networks, so that I can fund deployment transactions.

#### Acceptance Criteria

1. THE Execution_Plan SHALL provide wallet private key configuration steps for EVM-compatible chains (zkSync Sepolia, Optimism Sepolia, Arbitrum Sepolia), specifying that the private key must be stored in a `.env` file without the `0x` prefix
2. THE Execution_Plan SHALL provide Starknet account creation and keystore configuration steps using starkli, including setting the `STARKNET_ACCOUNT` and `STARKNET_KEYSTORE` environment variable paths
3. WHEN the Deployer needs zkSync Sepolia ETH, THE Execution_Plan SHALL document the process of obtaining Sepolia ETH from a faucet (providing at least one faucet URL) and bridging it to zkSync Sepolia via bridge.zksync.io, including an estimated bridge completion time of up to 15 minutes
4. WHEN the Deployer needs Starknet Sepolia ETH, THE Execution_Plan SHALL document the faucet URL (https://starknet-faucet.vercel.app/) and the account deployment process via starkli or a compatible wallet
5. WHEN the Deployer needs Optimism Sepolia ETH, THE Execution_Plan SHALL document the Alchemy faucet URL (https://www.alchemy.com/faucets/optimism-sepolia) for Optimism Sepolia
6. WHEN the Deployer needs Arbitrum Sepolia ETH, THE Execution_Plan SHALL document the Alchemy faucet URL (https://www.alchemy.com/faucets/arbitrum-sepolia) for Arbitrum Sepolia
7. THE Execution_Plan SHALL instruct the Deployer to use a single private key across all three EVM chains (zkSync Sepolia, Optimism Sepolia, Arbitrum Sepolia) stored in each project's `.env` file
8. THE Execution_Plan SHALL provide a verification step for each network instructing the Deployer to confirm a non-zero ETH balance before proceeding to deployment

### Requirement 3: Part A Deployment - zkSync ERC-20 Token

**User Story:** As a Deployer, I want step-by-step instructions to compile, deploy, and verify an ERC-20 token on zkSync Era Sepolia, so that I can complete Part A of the module.

#### Acceptance Criteria

1. WHEN the Deployer begins Part_A, THE Execution_Plan SHALL instruct running `npm install` in the `partA-zksync-erc20/` directory
2. THE Execution_Plan SHALL instruct the Deployer to copy `.env.example` to `.env` and set the PRIVATE_KEY variable without the `0x` prefix
3. WHEN dependencies are installed, THE Execution_Plan SHALL instruct running `npx hardhat compile` to compile the contract
4. WHEN compilation succeeds, THE Execution_Plan SHALL instruct running `npx hardhat deploy-zksync --script deploy.ts` to deploy and verify the contract on zkSync Sepolia
5. THE Execution_Plan SHALL instruct the Deployer to record the deployed contract address, deployment transaction hash, and the explorer URL from the console output
6. WHEN deployment and verification succeed, THE Execution_Plan SHALL instruct the Deployer to confirm the contract is visible at `https://sepolia-era.zksync.network/address/<CONTRACT_ADDRESS>#code`
7. IF compilation fails, THEN THE Execution_Plan SHALL instruct the Deployer to verify Node.js version is 18 or higher, delete `node_modules/`, and re-run `npm install`
8. IF deployment fails due to insufficient funds, THEN THE Execution_Plan SHALL direct the Deployer back to the testnet ETH acquisition step for zkSync Sepolia
9. IF verification fails but deployment succeeds, THEN THE Execution_Plan SHALL instruct the Deployer to manually verify using `npx hardhat verify --network zkSyncSepolia <CONTRACT_ADDRESS> "MyToken" "MTK"`

### Requirement 4: Part B Deployment - Cairo Simple Storage on Starknet

**User Story:** As a Deployer, I want step-by-step instructions to build, test, declare, and deploy a Cairo contract on Starknet Sepolia, so that I can complete Part B of the module.

#### Acceptance Criteria

1. WHEN the Deployer begins Part_B, THE Execution_Plan SHALL instruct setting the environment variables STARKNET_RPC, STARKNET_ACCOUNT, and STARKNET_KEYSTORE, then running `scarb build` in the `partB-cairo-storage/` directory
2. IF the build fails, THEN THE Execution_Plan SHALL instruct the Deployer to verify that Scarb is installed and the `Scarb.toml` dependencies are resolvable before retrying
3. WHEN the build succeeds, THE Execution_Plan SHALL instruct running `snforge test` and expecting 5 passing tests with 0 failures
4. IF any test fails, THEN THE Execution_Plan SHALL instruct the Deployer to review the test output, verify the contract source in `src/lib.cairo` matches the expected interface, and re-run tests before proceeding
5. WHEN tests pass, THE Execution_Plan SHALL instruct declaring the contract class using `starkli declare` with the artifact at `target/dev/simple_storage_SimpleStorage.contract_class.json`
6. WHEN declaration succeeds, THE Execution_Plan SHALL instruct deploying the contract using `starkli deploy` with the returned class hash and no constructor arguments
7. IF declaration fails with "class already declared", THEN THE Execution_Plan SHALL instruct the Deployer to proceed with the existing class hash
8. THE Execution_Plan SHALL instruct the Deployer to record the class hash, contract address, and transaction hashes in a local text file or document for submission
9. WHEN deployment succeeds, THE Execution_Plan SHALL instruct the Deployer to verify deployment by calling the `get` function using `starkli call` and confirming the returned value is `0x0`

### Requirement 5: Part C Deployment - LayerZero OApp Cross-Chain Messaging

**User Story:** As a Deployer, I want step-by-step instructions to deploy, configure, and test a cross-chain messenger on Optimism Sepolia and Arbitrum Sepolia, so that I can complete Part C of the module.

#### Acceptance Criteria

1. WHEN the Deployer begins Part_C, THE Execution_Plan SHALL instruct running `npm install` and `forge install foundry-rs/forge-std --no-commit` in the `partC-layerzero-oapp/` directory
2. WHEN dependencies are installed, THE Execution_Plan SHALL instruct the Deployer to copy `.env.example` to `.env` and configure PRIVATE_KEY (without 0x prefix), OPTIMISM_SEPOLIA_RPC_URL, ARBITRUM_SEPOLIA_RPC_URL, ETHERSCAN_API_KEY, and ARBISCAN_API_KEY
3. WHEN the `.env` file is configured, THE Execution_Plan SHALL instruct running `forge build` to compile the contracts
4. WHEN compilation succeeds, THE Execution_Plan SHALL instruct running `forge test -vvv` to execute the test suite
5. WHEN tests pass, THE Execution_Plan SHALL instruct deploying the CrossChainMessenger contract on Optimism Sepolia by running `forge script script/Deploy.s.sol --rpc-url optimism_sepolia --broadcast --verify` and recording the deployed contract address from the console output
6. WHEN the Optimism deployment succeeds, THE Execution_Plan SHALL instruct deploying the CrossChainMessenger contract on Arbitrum Sepolia by running `forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --broadcast --verify` and recording the deployed contract address from the console output
7. WHEN both deployments succeed, THE Execution_Plan SHALL instruct configuring Peer_Configuration on Optimism Sepolia by setting environment variables MESSENGER_ADDRESS to the Optimism contract address, REMOTE_EID to 40231, and REMOTE_MESSENGER_ADDRESS to the Arbitrum contract address, then running `forge script script/SetPeer.s.sol --rpc-url optimism_sepolia --broadcast`
8. WHEN Optimism Sepolia Peer_Configuration succeeds, THE Execution_Plan SHALL instruct configuring Peer_Configuration on Arbitrum Sepolia by setting environment variables MESSENGER_ADDRESS to the Arbitrum contract address, REMOTE_EID to 40232, and REMOTE_MESSENGER_ADDRESS to the Optimism contract address, then running `forge script script/SetPeer.s.sol --rpc-url arbitrum_sepolia --broadcast`
9. WHEN Peer_Configuration is complete on both chains, THE Execution_Plan SHALL instruct sending a Cross_Chain_Message from Optimism Sepolia to Arbitrum Sepolia by setting MESSENGER_ADDRESS to the Optimism contract address, DST_EID to 40231, and MESSAGE to a test string, then running `forge script script/SendMessage.s.sol --rpc-url optimism_sepolia --broadcast`
10. WHEN the Cross_Chain_Message transaction is confirmed, THE Execution_Plan SHALL instruct the Deployer to wait 2-5 minutes for LayerZero relay and then verify message receipt on Arbitrum Sepolia by running `cast call <arbitrum_contract_address> "lastMessage()(string)" --rpc-url $ARBITRUM_SEPOLIA_RPC_URL` and confirming the returned string matches the sent message
11. IF deployment or peer configuration fails, THEN THE Execution_Plan SHALL instruct the Deployer to verify that the wallet has sufficient testnet ETH on the target chain and that all environment variables are correctly set before retrying
12. WHEN all steps are complete, THE Execution_Plan SHALL instruct the Deployer to record the contract addresses for both chains and the transaction hashes for the deployment, SetPeer, and SendMessage transactions

### Requirement 6: Documentation of Deployment Results

**User Story:** As a Deployer, I want instructions to update the README.md with all deployed addresses and transaction hashes, so that I have a permanent record of the deployment.

#### Acceptance Criteria

1. WHEN all deployments are complete, THE Execution_Plan SHALL instruct the Deployer to update the root README.md Part A section by replacing `<DEPLOYED_CONTRACT_ADDRESS>` with the actual zkSync Sepolia contract address and replacing `<DEPLOYMENT_TX_HASH>` with the actual transaction hash
2. THE Execution_Plan SHALL instruct the Deployer to update the root README.md Part B section by replacing `<DEPLOYED_CONTRACT_ADDRESS>` with the actual Starknet Sepolia contract address and replacing `<DEPLOYMENT_TX_HASH>` with the actual declaration or deployment transaction hash
3. THE Execution_Plan SHALL instruct the Deployer to update the root README.md Part C table by replacing `<OP_CONTRACT_ADDRESS>` and `<ARB_CONTRACT_ADDRESS>` with the actual Optimism Sepolia and Arbitrum Sepolia contract addresses, and replacing `<OP_TX_HASH>` and `<ARB_TX_HASH>` with the actual deployment transaction hashes
4. THE Execution_Plan SHALL instruct the Deployer to replace `<PASTE TEST OUTPUT HERE>` in the README.md with the full output of `forge test -vvv` from Part C
5. THE Execution_Plan SHALL instruct the Deployer to replace `<YOUR_TX_HASH>` in the Part A bridging section with the actual bridge transaction hash from the zkSync ETH bridge

### Requirement 7: Execution Order and Dependencies

**User Story:** As a Deployer, I want a clear execution order with dependency information, so that I complete steps in the correct sequence without errors.

#### Acceptance Criteria

1. THE Execution_Plan SHALL specify that toolchain installation (Node.js, Foundry, Scarb, and starkli or sncast) is verified as available before any deployment steps begin
2. THE Execution_Plan SHALL specify that testnet ETH acquisition on zkSync Sepolia, Starknet Sepolia, Optimism Sepolia, and Arbitrum Sepolia is confirmed with a non-zero balance before the corresponding deployment on that network
3. THE Execution_Plan SHALL specify that Part_A, Part_B, and Part_C deployments can be executed in any order after toolchain installation and the corresponding network's testnet ETH acquisition are confirmed complete
4. THE Execution_Plan SHALL specify that within Part_C, contract deployment on both Optimism Sepolia and Arbitrum Sepolia is confirmed with a deployed contract address before Peer_Configuration begins
5. THE Execution_Plan SHALL specify that within Part_C, Peer_Configuration on both Optimism Sepolia and Arbitrum Sepolia is confirmed with a successful transaction before sending a Cross_Chain_Message
6. THE Execution_Plan SHALL specify that documentation updates to the README.md deployment records are performed after all Part_A, Part_B, and Part_C deployments and verifications are complete
7. IF a prerequisite step fails or cannot be confirmed as complete, THEN THE Execution_Plan SHALL indicate that dependent steps are blocked until the prerequisite is successfully retried and confirmed
