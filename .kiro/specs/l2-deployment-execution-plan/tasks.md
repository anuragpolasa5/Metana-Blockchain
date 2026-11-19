# Tasks

## Task 1: Toolchain Installation
- [x] Verify Node.js >= 18 is installed (`node --version`)
- [x] Verify Foundry is installed with Solidity 0.8.24 support (`forge --version`)
- [x] Verify Scarb is installed for Cairo edition 2024_07 (`scarb --version`)
- [x] Verify starkli is installed for Starknet Sepolia (`starkli --version`)
- [x] Verify snforge v0.34.0 is installed (`snforge --version`)

## Task 2: Wallet Setup and Testnet ETH
- [x] Export/generate private key for EVM chains (without 0x prefix)
- [ ] Get Sepolia ETH from faucet
- [ ] Bridge ETH to zkSync Sepolia via bridge.zksync.io (record TX hash)
- [ ] Get Starknet Sepolia ETH from faucet
- [ ] Create and deploy Starknet account via starkli
- [ ] Get Optimism Sepolia ETH from Alchemy faucet
- [ ] Get Arbitrum Sepolia ETH from Alchemy faucet
- [ ] Verify non-zero balance on all 4 networks

## Task 3: Part A - zkSync ERC-20 Deployment
- [x] Run `npm install` in `partA-zksync-erc20/`
- [x] Copy `.env.example` to `.env` and set PRIVATE_KEY
- [x] Run `npx hardhat compile`
- [ ] Run `npx hardhat deploy-zksync --script deploy.ts`
- [ ] Record contract address and TX hash
- [ ] Confirm contract verified at explorer URL

## Task 4: Part B - Cairo Simple Storage Deployment
- [x] Set STARKNET_RPC, STARKNET_ACCOUNT, STARKNET_KEYSTORE env vars
- [x] Run `scarb build` in `partB-cairo-storage/`
- [x] Run `snforge test` (expect 5 passing tests)
- [ ] Run `starkli declare` with Sierra artifact
- [ ] Run `starkli deploy` with class hash
- [ ] Verify deployment with `starkli call <ADDRESS> get` (expect 0x0)
- [ ] Record class hash, contract address, TX hashes

## Task 5: Part C - LayerZero OApp Deployment
- [x] Run `npm install` and `forge install foundry-rs/forge-std --no-commit`
- [x] Copy `.env.example` to `.env` and configure all variables
- [x] Run `forge build`
- [x] Run `forge test -vvv` (save output)
- [ ] Deploy on Optimism Sepolia (record address)
- [ ] Deploy on Arbitrum Sepolia (record address)
- [ ] Set peer on Optimism (REMOTE_EID=40231, point to Arbitrum contract)
- [ ] Set peer on Arbitrum (REMOTE_EID=40232, point to Optimism contract)
- [ ] Send cross-chain message from Optimism to Arbitrum
- [ ] Wait 2-5 min, verify `lastMessage()` on Arbitrum matches sent message
- [ ] Record all TX hashes

## Task 6: Documentation Update
- [ ] Update README.md Part A: replace placeholders with actual addresses/hashes
- [ ] Update README.md Part B: replace placeholders with actual addresses/hashes
- [ ] Update README.md Part C: replace placeholders with actual addresses/hashes
- [ ] Paste `forge test -vvv` output into README.md test results section
- [ ] Record bridge TX hash in Part A bridging section
