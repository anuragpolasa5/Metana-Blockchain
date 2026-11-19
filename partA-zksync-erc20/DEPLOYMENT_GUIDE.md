# Part A - zkSync ERC-20 Token: Complete Deployment Guide

## Requirement Coverage
| ID | Behaviour | Status |
|----|-----------|--------|
| L2-1 | Bridge transaction URL documented | Covered below |
| L2-2 | ERC20 inheriting OZ's ERC20 contract | `contracts/MyToken.sol` |
| L2-3 | Name and symbol passed to constructor | deploy script passes "MyToken", "MTK" |
| L2-4 | Deploy and verify on zkSync Sepolia | Steps 4-5 below |

---

## Phase 0: Toolchain Verification

Before starting, confirm these tools are installed and meet minimum versions:

```bash
node --version        # Must be >= v18.0.0
npm --version         # Must be >= 9.0.0
```

If Node.js is below v18, download from https://nodejs.org/en/download/ or use nvm:
```bash
nvm install 18
nvm use 18
```

---

## Phase 1: Wallet Setup and Testnet ETH Acquisition (L2-1)

### 1.1 Generate or Export Private Key

Use MetaMask or any EVM wallet. Export the private key (without the `0x` prefix).

> IMPORTANT: Use the SAME private key for all three EVM projects (zkSync, Optimism, Arbitrum) to simplify management.

### 1.2 Get Sepolia ETH from Faucet

Visit one of these faucets and request Sepolia ETH:
- https://sepoliafaucet.com/
- https://www.alchemy.com/faucets/ethereum-sepolia
- https://faucets.chain.link/sepolia

### 1.3 Bridge Sepolia ETH to zkSync Sepolia

1. Go to https://bridge.zksync.io/
2. Connect your wallet
3. Switch network to **Sepolia Testnet**
4. Enter the amount of ETH to bridge (recommend 0.05+ ETH)
5. Click "Deposit" and confirm the transaction
6. Wait for bridge completion (~15 minutes)

**Record your bridge transaction hash:**
```
Bridge TX: https://sepolia.etherscan.io/tx/<YOUR_BRIDGE_TX_HASH>
```

### 1.4 Verify Balance on zkSync Sepolia

Check your balance at: https://sepolia-era.zksync.network/address/<YOUR_WALLET_ADDRESS>

Or use cast (if Foundry is installed):
```bash
cast balance <YOUR_WALLET_ADDRESS> --rpc-url https://sepolia.era.zksync.dev
```

> DO NOT proceed to deployment until you confirm a non-zero ETH balance on zkSync Sepolia.

---

## Phase 2: Project Setup

### 2.1 Install Dependencies

```bash
cd partA-zksync-erc20
npm install
```

If installation fails:
1. Verify Node.js version: `node --version` (must be >= 18)
2. Delete node_modules and retry:
   ```bash
   rmdir /s /q node_modules
   del package-lock.json
   npm install
   ```

### 2.2 Configure Environment

```bash
copy .env.example .env
```

Edit `.env` and set your private key (WITHOUT the `0x` prefix):
```
PRIVATE_KEY=your_private_key_here_without_0x_prefix
```

---

## Phase 3: Compile the Contract (L2-2)

```bash
npx hardhat compile
```

Expected output:
```
Compiling 1 Solidity file
Successfully compiled 1 Solidity file
```

**If compilation fails:**
1. Check Node.js version is >= 18
2. Delete `node_modules/` and `artifacts-zk/` and `cache-zk/`
3. Re-run `npm install` then `npx hardhat compile`

---

## Phase 4: Deploy and Verify (L2-3, L2-4)

```bash
npx hardhat deploy-zksync --script deploy.ts
```

This single command will:
1. Deploy the MyToken contract with constructor args: `name = "MyToken"`, `symbol = "MTK"` (L2-3)
2. Mint 1,000,000 MTK to the deployer address
3. Automatically verify the contract on zkSync Sepolia explorer (L2-4)

**Expected console output:**
```
Deploying MyToken (MTK) on zkSync Era...

--- Deployment Successful ---
Token Name: MyToken
Token Symbol: MTK
Contract Address: 0x...
Explorer: https://sepolia-era.zksync.network/address/0x...

Verifying contract...
Contract verified successfully!
Verified at: https://sepolia-era.zksync.network/address/0x...#code
```

### Record These Values:
```
Contract Address: ___________________________________
Deployment TX Hash: ___________________________________
Explorer URL: https://sepolia-era.zksync.network/address/<ADDRESS>
Verified URL: https://sepolia-era.zksync.network/address/<ADDRESS>#code
```

---

## Phase 5: Verify Deployment

1. Open the explorer link in your browser: `https://sepolia-era.zksync.network/address/<CONTRACT_ADDRESS>#code`
2. Confirm the contract source code is visible and verified
3. Check the "Read Contract" tab to verify:
   - `name()` returns "MyToken"
   - `symbol()` returns "MTK"
   - `totalSupply()` returns 1000000000000000000000000 (1M with 18 decimals)

---

## Phase 6: Troubleshooting

### Deployment fails with "insufficient funds"
→ Go back to Phase 1.3 and bridge more ETH to zkSync Sepolia.

### Verification fails but deployment succeeds
Run manual verification:
```bash
npx hardhat verify --network zkSyncSepolia <CONTRACT_ADDRESS> "MyToken" "MTK"
```

### "Cannot estimate gas" error
→ Your wallet may not have enough ETH. Check balance on zkSync Sepolia explorer.

### "Nonce too low" error
→ A previous transaction may be pending. Wait 1-2 minutes and retry.

---

## Phase 7: Update Documentation

After successful deployment, update the root `README.md`:
1. Replace `<DEPLOYED_CONTRACT_ADDRESS>` with your actual contract address
2. Replace `<DEPLOYMENT_TX_HASH>` with your actual deployment transaction hash
3. Replace `<YOUR_TX_HASH>` in the bridging section with your bridge transaction hash

---

## Summary Checklist

- [ ] Node.js >= 18 installed
- [ ] Sepolia ETH obtained from faucet
- [ ] ETH bridged to zkSync Sepolia (TX hash recorded)
- [ ] `npm install` completed successfully
- [ ] `.env` configured with private key
- [ ] Contract compiled with `npx hardhat compile`
- [ ] Contract deployed with `npx hardhat deploy-zksync --script deploy.ts`
- [ ] Contract address and TX hash recorded
- [ ] Contract verified on explorer (source code visible)
- [ ] README.md updated with deployment details
