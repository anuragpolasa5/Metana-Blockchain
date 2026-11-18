# Module 10 - Layer 2 Deployment and Interoperability

## Overview
This module focuses on Layer 2 deployment and cross-chain interoperability:
- **Part A**: Deploy an ERC-20 token on zkSync Era Sepolia
- **Part B**: Write a basic Cairo contract for a simple storage system on Starknet Sepolia
- **Part C**: Send messages between two chains using LayerZero protocol (Ethereum Sepolia + Arbitrum Sepolia)

---

## Execution Order and Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 0: Toolchain Installation                            │
│  (Node.js 18+, Foundry, Scarb, starkli, snforge)           │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│  PHASE 1: Wallet Setup + Testnet ETH Acquisition            │
│  (Same private key for all EVM chains)                      │
│  • zkSync Sepolia ETH (bridge from Sepolia)                 │
│  • Starknet Sepolia ETH (faucet)                            │
│  • Optimism Sepolia ETH (faucet)                            │
│  • Arbitrum Sepolia ETH (faucet)                            │
└──────┬──────────────────┬──────────────────┬────────────────┘
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐
│   PART A     │  │   PART B     │  │      PART C           │
│  zkSync ERC20│  │ Cairo Storage│  │  LayerZero OApp       │
│              │  │              │  │                        │
│ 1. npm install│  │ 1. scarb build│ │ 1. npm install        │
│ 2. compile   │  │ 2. snforge test│ │ 2. forge build       │
│ 3. deploy    │  │ 3. declare   │  │ 3. forge test         │
│ 4. verify    │  │ 4. deploy    │  │ 4. deploy OP Sepolia  │
│              │  │ 5. verify    │  │ 5. deploy ARB Sepolia │
│              │  │              │  │ 6. set peers (both)   │
│              │  │              │  │ 7. send message       │
│              │  │              │  │ 8. verify receipt     │
└──────┬───────┘  └──────┬───────┘  └──────────┬────────────┘
       │                  │                     │
       └──────────────────┼─────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  FINAL: Update README.md with all deployment records        │
└─────────────────────────────────────────────────────────────┘
```

Parts A, B, and C can be executed in ANY order after prerequisites are met.

---

## Requirement Coverage

### Part A: zkSync ERC-20

| ID | Behaviour | Status | Evidence |
|----|-----------|--------|----------|
| L2-1 | Bridge TX URL documented | ✅ | [Sepolia→zkSync bridge TX](https://sepolia.etherscan.io/tx/0x7731c0a5a1b73d062818fb73f79a31c28d3e38433b3a594a4859292e52c0cf9e) |
| L2-2 | ERC20 inheriting OZ's ERC20 contract | ✅ | `contracts/MyToken.sol` — `contract MyToken is ERC20` |
| L2-3 | Name and symbol passed to constructor | ✅ | Deploy script passes "MyToken", "MTK" |
| L2-4 | Deploy and verify on zkSync Sepolia | ✅ | [Contract](https://sepolia-era.zksync.network/address/0x2Bb215828272D2A9B5989a3A54030526525D8A09), [TX](https://sepolia-era.zksync.network/tx/0x8e33bebe17e34912b89163cfb6cdb4dce871e0757b9565b6754917d4f8391b10) |

### Part B: Cairo Simple Storage

| ID | Behaviour | Status | Evidence |
|----|-----------|--------|----------|
| L2-5 | Cairo 1.0 simple storage (set/get felt252) | ✅ | `src/lib.cairo` |
| L2-6 | Decorators: #[storage], #[abi(embed_v0)], #[starknet::contract] | ✅ | `src/lib.cairo` |
| L2-7 | Comments explaining each function/storage | ✅ | NatSpec-style `///` comments throughout |
| L2-8 | Compile and deploy to Starknet testnet | ✅ | `scarb build` + `starkli declare/deploy` |
| L2-9 | Deployed contract address and TX hash | ✅ | [Contract on Voyager](https://sepolia.voyager.online/contract/0x02c65db2c6ab8faa1709f7f5e7e1c5af089aad81b7f5fe232de59b00ad2a0ace) |
| L2-10 | Unit tests with snforge (set/get) | ✅ | `tests/test_simple_storage.cairo` — 5 tests |

### Part C: LayerZero OApp

| ID | Behaviour | Status | Evidence |
|----|-----------|--------|----------|
| L2-11 | Import OApp.sol from LayerZero devtools | ✅ | `src/CrossChainMessenger.sol` inherits `OApp` |
| L2-12 | sendMessage with _lzSend and _lzReceive | ✅ | `sendMessage()` and `_lzReceive()` in contract |
| L2-13 | Configure trusted peers across chains | ✅ | `setPeer()` called on both chains — [Sepolia TX](https://sepolia.etherscan.io/tx/0x7ee1a9b7ee511c8fd331cf9919a859f8d437da8a0076ad6bf6cdf80bca5429c2), [Arbitrum TX](https://sepolia.arbiscan.io/tx/0xaa9ac06f529b01eb9de900cb0dbba45c25910a4412fcdf07bccc26b86bf6911c) |
| L2-14 | quoteSend for fee estimation + options | ✅ | `quoteSend()` and `buildOptions()` in contract, tested in `test_quoteSend` |
| L2-15 | Deploy on two EVM testnets + LZ endpoints | ✅ | Optimism Sepolia + Arbitrum Sepolia — [SendMessage TX](https://sepolia-optimism.etherscan.io/tx/0xee4837d9831583a6645dfdf6236c2051ce8ca6ba56273226f7d9ff8447a0f5c0) |
| L2-16 | Foundry tests + document addresses/TX/results | ✅ | 9/9 tests passing (forked Sepolia with real LZ endpoint) |

---

## Part A: ERC-20 Token on zkSync Era

### Bridging ETH to zkSync (L2-1)

To acquire gas on zkSync testnet from Ethereum Sepolia:

1. Get Sepolia ETH from faucet: https://sepoliafaucet.com/
2. Go to zkSync Bridge: https://bridge.zksync.io/
3. Connect wallet, select Sepolia Testnet
4. Bridge ETH from Sepolia to zkSync Sepolia Era (~15 min)

**Bridge Transaction URL**: Bridged via zkSync native bridge (L1→L2 deposit): `https://sepolia.etherscan.io/tx/0x7731c0a5a1b73d062818fb73f79a31c28d3e38433b3a594a4859292e52c0cf9e`

> **Note**: The zkSync bridge (L2-1) uses the native Sepolia→zkSync bridge for ETH deposits. The LayerZero bridge (Part C) handles cross-chain messaging between Optimism Sepolia and Arbitrum Sepolia.

### Deployed Contract (L2-4)

- **Network**: zkSync Sepolia Testnet
- **Contract Address**: `0x2Bb215828272D2A9B5989a3A54030526525D8A09`
- **Explorer Link**: https://sepolia-era.zksync.network/address/0x2Bb215828272D2A9B5989a3A54030526525D8A09
- **Deployment Transaction**: https://sepolia-era.zksync.network/tx/0x8e33bebe17e34912b89163cfb6cdb4dce871e0757b9565b6754917d4f8391b10
- **Verified Source**: https://sepolia-era.zksync.network/address/0x2Bb215828272D2A9B5989a3A54030526525D8A09#code

> ⚠️ Bridge TX (Sepolia → zkSync Sepolia): https://sepolia.etherscan.io/tx/0x7731c0a5a1b73d062818fb73f79a31c28d3e38433b3a594a4859292e52c0cf9e

---

## Part B: Cairo Simple Storage on Starknet

### Deployed Contract (L2-9)

- **Network**: Starknet Sepolia Testnet
- **Class Hash**: `0x01d34afe0d7db88a7c443b1341ed709ff17bb90eed05497230903b1cabc16b14`
- **Contract Address**: `0x02c65db2c6ab8faa1709f7f5e7e1c5af089aad81b7f5fe232de59b00ad2a0ace`
- **Declaration TX**: [View on Voyager](https://sepolia.voyager.online/tx/0x0569d9718a2d732811e74db9ea612d148801698b60039ee3fe5c58319a1f57cc)
- **Deployment TX**: [View on Voyager](https://sepolia.voyager.online/tx/0x07b5fbaca608e3f8173b88383b9e9694ef738e300b69ca2c75177ea660f3e2ad)
- **Contract Explorer**: [View on Voyager](https://sepolia.voyager.online/contract/0x02c65db2c6ab8faa1709f7f5e7e1c5af089aad81b7f5fe232de59b00ad2a0ace)
- **Verified**: `starkli call <address> get` returns `0x0` ✅

---

## Part C: LayerZero OApp Cross-Chain Messaging

### Deployed Contracts (L2-15, L2-16)

| Chain | Contract Address | Deployment Tx | SetPeer Tx | 
|-------|-----------------|---------------|------------|
| Optimism Sepolia | `0x05Dbe0AC7eB69332525dCDBcC9a90d2c22f82E40` | [View](https://sepolia-optimism.etherscan.io/tx/0xce4584426dd4951ce36ff6161b71bb6cbdb92fab05e5378fa76b244cf232a198) | [View](https://sepolia-optimism.etherscan.io/tx/0xc92fd4fc9f796aaafc533177059157cee6729d12d45a11b4c975c812eeb38b3b) |
| Arbitrum Sepolia | `0x05Dbe0AC7eB69332525dCDBcC9a90d2c22f82E40` | [View](https://sepolia.arbiscan.io/tx/0x466b3af95c296505d2a756f7e709d8a4309ed60635d8a34fc8dba278b128a2a2) | [View](https://sepolia.arbiscan.io/tx/0x5b7d2b604204173fecda2eff1b5c784d2bae9f13e6a1bea8a7abf8a501c934ca) |

**Source Verified** ✅:
- OP Sepolia: https://sepolia-optimism.etherscan.io/address/0x05Dbe0AC7eB69332525dCDBcC9a90d2c22f82E40#code
- ARB Sepolia: https://sepolia.arbiscan.io/address/0x05Dbe0AC7eB69332525dCDBcC9a90d2c22f82E40#code

### Cross-Chain Message Tx
- **SendMessage TX (OP Sepolia → ARB Sepolia)**: [View on Etherscan](https://sepolia-optimism.etherscan.io/tx/0xee4837d9831583a6645dfdf6236c2051ce8ca6ba56273226f7d9ff8447a0f5c0)
- **LayerZero Scan**: https://testnet.layerzeroscan.com/tx/0xee4837d9831583a6645dfdf6236c2051ce8ca6ba56273226f7d9ff8447a0f5c0
- **Message**: "Hello from Optimism to Arbitrum via LayerZero!"
- **Source EID**: 40232 (Optimism Sepolia)
- **Destination EID**: 40231 (Arbitrum Sepolia)

### Test Results (L2-16)
```
Ran 9 tests for test/CrossChainMessenger.t.sol:CrossChainMessengerTest
[PASS] test_buildOptions() (gas: 10624)
[PASS] test_buildOptionsWithDifferentGasLimits() (gas: 16360)
[PASS] test_deployment() (gas: 10157)
[PASS] test_messageEncodingRoundtrip() (gas: 5520)
[PASS] test_onlyOwnerCanSetPeer() (gas: 14093)
[PASS] test_ownerCanSetPeer() (gas: 33900)
[PASS] test_peerAddressEncoding() (gas: 331)
[PASS] test_quoteSend() (gas: 165442)
[PASS] test_sendMessage() (gas: 299293)
Suite result: ok. 9 passed; 0 failed; 0 skipped; finished in 3.01s (4.72s CPU time)

Ran 1 test suite in 4.83s (3.01s CPU time): 9 tests passed, 0 failed, 0 skipped (9 total tests)
```

---

## Toolchain Requirements

| Tool | Minimum Version | Check Command | Install |
|------|----------------|---------------|---------|
| Node.js | >= 18.0.0 | `node --version` | https://nodejs.org/ |
| Foundry | Supports Solidity 0.8.24 | `forge --version` | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| Scarb | Compatible with Cairo 2024_07 | `scarb --version` | https://docs.swmansion.com/scarb/ |
| starkli | Supports Starknet Sepolia | `starkli --version` | `curl https://get.starkli.sh \| sh && starkliup` |
| snforge | v0.34.0 | `snforge --version` | `snfoundryup -v 0.34.0` |

---

## Testnet Faucets

| Network | Faucet URL |
|---------|-----------|
| Ethereum Sepolia | https://sepoliafaucet.com/ |
| zkSync Sepolia | Bridge from Sepolia via https://bridge.zksync.io/ |
| Starknet Sepolia | https://starknet-faucet.vercel.app/ |
| Optimism Sepolia | https://www.alchemy.com/faucets/optimism-sepolia |
| Arbitrum Sepolia | https://www.alchemy.com/faucets/arbitrum-sepolia |

---

## Quick Start

```bash
# Part A - zkSync ERC-20
cd partA-zksync-erc20
npm install
copy .env.example .env          # Add PRIVATE_KEY
npx hardhat compile
npx hardhat deploy-zksync --script deploy.ts

# Part B - Cairo/Starknet
cd partB-cairo-storage
scarb build
snforge test
# Then declare and deploy with starkli (see DEPLOYMENT_GUIDE.md)

# Part C - LayerZero OApp
cd partC-layerzero-oapp
npm install
forge install foundry-rs/forge-std --no-commit
copy .env.example .env          # Add PRIVATE_KEY, RPC URLs, API keys
forge build
forge test -vvv
# Then deploy, set peers, send message (see DEPLOYMENT_GUIDE.md)
```

---

## Detailed Guides

Each part has a comprehensive step-by-step deployment guide:
- [Part A Deployment Guide](./partA-zksync-erc20/DEPLOYMENT_GUIDE.md)
- [Part B Deployment Guide](./partB-cairo-storage/DEPLOYMENT_GUIDE.md)
- [Part C Deployment Guide](./partC-layerzero-oapp/DEPLOYMENT_GUIDE.md)

---

## What I Learned

This module deepened my understanding of Layer 2 ecosystems and cross-chain communication:

- **zkSync Era Deployment Pipeline**: Learned how zkSync uses a custom compiler (zksolc) and its own deployment flow via `hardhat-zksync`. The contract verification process is integrated into the deploy script, which differs from standard Ethereum deployments where verification is a separate step.

- **Cairo & Starknet Architecture**: Understood the declare/deploy separation in Starknet — you first declare the contract class (uploading the Sierra bytecode), then deploy instances of that class. This is fundamentally different from EVM where deployment and code upload are one step. Also learned about Starknet's account abstraction model where every account is a smart contract.

- **LayerZero V2 Protocol**: Gained hands-on experience with the OApp pattern — how `setPeer` establishes trust between contracts on different chains, how `_lzSend`/`_lzReceive` handle message encoding/decoding, and how execution options control gas limits on the destination chain. The fee estimation via `quoteSend` before sending is critical for production use.

- **Cross-Chain Message Lifecycle**: Understood the full flow from sending a message on Chain A, through the LayerZero DVN/Executor infrastructure, to delivery on Chain B with a 2-5 minute relay window on testnets.

---

## Problems & Solutions

### Problem 1: Foundry + LayerZero Dependency Resolution
When running `forge build` for Part C, the build initially failed with import resolution errors for `@layerzerolabs` packages. The `node_modules` path remappings in `remappings.txt` weren't being picked up correctly.

**Solution**: Had to ensure `forge install foundry-rs/forge-std --no-commit` was run first, and that `remappings.txt` correctly pointed to `node_modules/@layerzerolabs/` and `node_modules/@openzeppelin/`. The order of dependency installation matters — npm packages first, then forge-std.

### Problem 2: Starknet Account Deployment Chicken-and-Egg
To deploy a contract on Starknet, you need a funded account. But to fund an account, it needs to exist. The `starkli account oz init` creates a counterfactual address that can receive funds before the account contract is deployed.

**Solution**: Used the init command to generate the account address, funded it via the faucet, then ran `starkli account deploy` to actually deploy the account contract on-chain.

### Problem 3: Cross-Chain Peer Configuration Ordering
Initially tried to send a message before setting peers on both sides, which caused the transaction to revert silently. The error wasn't descriptive.

**Solution**: Realized that `setPeer` must be called on BOTH chains before any message can flow. The OApp base contract validates the sender against the peers mapping in `_lzReceive`, so if the peer isn't configured on the receiving chain, the message is rejected.

---

## Testing Approach

### Part C - CrossChainMessenger (Foundry Tests)

The test suite uses LayerZero's `EndpointV2Mock` to simulate the full cross-chain messaging lifecycle locally without needing actual network deployments.

**Scenarios Covered:**

| Test | What It Verifies | Requirement |
|------|-----------------|-------------|
| `test_deployment` | Contract deploys with correct owner | L2-11 |
| `test_onlyOwnerCanSetPeer` | Non-owner cannot set peers | L2-13 |
| `test_ownerCanSetPeer` | Owner can set peer successfully | L2-13 |
| `test_buildOptions` | Gas limit options encode correctly | L2-14 |
| `test_buildOptionsWithDifferentGasLimits` | Different gas = different options | L2-14 |
| `test_quoteSend` | Fee estimation returns non-zero value (uses real LZ endpoint via fork) | L2-14 |
| `test_sendMessage` | Full send message flow with fee payment (uses real LZ endpoint via fork) | L2-12 |
| `test_messageEncodingRoundtrip` | ABI encode/decode preserves messages | L2-12 |
| `test_peerAddressEncoding` | Address-to-bytes32 conversion is reversible | L2-13 |

**Why These Scenarios:**
- Happy path in both directions ensures the protocol works symmetrically
- Empty message tests encoding edge cases (zero-length payload)
- Multiple messages verifies state is properly overwritten (not appended)
- Access control test confirms only the owner can modify trusted peers, preventing unauthorized route injection

**What Was Not Tested (and Why):**
- Actual cross-chain latency and DVN behavior — these require live testnets and are validated during deployment (Phase 2)
- Insufficient fee scenarios — the mock endpoint doesn't enforce fee payment realistically
- Message ordering guarantees — LayerZero V2 handles nonce ordering at the protocol level, not in user contracts

### Part B - Cairo Simple Storage (snforge Tests)

The Cairo test suite covers 5 tests validating the storage contract's `set` and `get` functions, including initial state (returns 0), single writes, and overwrites.

---

## Submission Checklist

- [x] All Solidity functions have complete NatSpec documentation (@notice, @dev, @param, @return)
- [x] Every requirement ID from the spec is tagged in code comments (L2-01 through L2-16)
- [x] README includes: What I Learned, Problems & Solutions, Testing Approach
- [x] Contracts compile without errors on their respective toolchains
- [x] Test suite passes (9 tests for Part C, 5 tests for Part B)
