# Part C - LayerZero OApp Cross-Chain Messaging: Complete Deployment Guide

## Requirement Coverage
| ID | Behaviour | Status |
|----|-----------|--------|
| L2-11 | Install LZ devtools, import OApp.sol | `package.json` + `src/CrossChainMessenger.sol` |
| L2-12 | sendMessage with _lzSend and _lzReceive | `src/CrossChainMessenger.sol` |
| L2-13 | Configure trusted peers across chains | `script/SetPeer.s.sol` |
| L2-14 | quoteSend for fee estimation + execution options | `src/CrossChainMessenger.sol` |
| L2-15 | Deploy on Optimism Sepolia + Arbitrum Sepolia | Steps 5-6 below |
| L2-16 | Foundry tests + documentation | `test/CrossChainMessenger.t.sol` |

---

## Phase 0: Toolchain Verification

Before starting, confirm these tools are installed:

```bash
node --version        # Must be >= v18.0.0
forge --version       # Must support Solidity 0.8.24
cast --version        # Included with Foundry
```

### Install Foundry (if not installed)
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

On Windows (PowerShell):
```powershell
# Download foundryup and run it
irm https://foundry.paradigm.xyz | iex
foundryup
```

If Foundry version doesn't support Solidity 0.8.24, run `foundryup` to update.

---

## Phase 1: Wallet Setup and Testnet ETH Acquisition

### 1.1 Private Key

Use the SAME private key as Part A (without `0x` prefix). You need testnet ETH on BOTH chains.

### 1.2 Get Optimism Sepolia ETH

1. Visit: https://www.alchemy.com/faucets/optimism-sepolia
2. Enter your wallet address
3. Request testnet ETH

Verify balance:
```bash
cast balance <YOUR_ADDRESS> --rpc-url https://sepolia.optimism.io
```

### 1.3 Get Arbitrum Sepolia ETH

1. Visit: https://www.alchemy.com/faucets/arbitrum-sepolia
2. Enter your wallet address
3. Request testnet ETH

Verify balance:
```bash
cast balance <YOUR_ADDRESS> --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

> DO NOT proceed until you have non-zero ETH on BOTH Optimism Sepolia AND Arbitrum Sepolia.

---

## Phase 2: Project Setup (L2-11)

### 2.1 Install Dependencies

```bash
cd partC-layerzero-oapp
npm install
forge install foundry-rs/forge-std --no-commit
```

### 2.2 Configure Environment

```bash
copy .env.example .env
```

Edit `.env` with your values:
```env
# Deployer private key (WITHOUT 0x prefix)
PRIVATE_KEY=your_private_key_here_without_0x_prefix

# RPC URLs
OPTIMISM_SEPOLIA_RPC_URL=https://sepolia.optimism.io
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc

# Block explorer API keys (for contract verification)
ETHERSCAN_API_KEY=your_optimism_etherscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key
```

> Get API keys from:
> - Optimism: https://optimistic.etherscan.io/myapikey
> - Arbitrum: https://arbiscan.io/myapikey

---

## Phase 3: Compile Contracts

```bash
forge build
```

**Expected output:**
```
[⠊] Compiling...
[⠊] Compiling X files
[⠒] Solc 0.8.24 finished in X.XXs
Compiler run successful!
```

**If compilation fails:**
1. Verify `remappings.txt` paths match your `node_modules/` structure
2. Run `npm install` again
3. Check that `forge-std` is in `lib/`: `forge install foundry-rs/forge-std --no-commit`

---

## Phase 4: Run Tests (L2-16)

```bash
forge test -vvv
```

**Expected output (all tests passing):**
```
Running 8 tests for test/CrossChainMessenger.t.sol:CrossChainMessengerTest
[PASS] test_buildOptions()
[PASS] test_deployment()
[PASS] test_multipleMessages()
[PASS] test_onlyOwnerCanSetPeer()
[PASS] test_peersConfigured()
[PASS] test_quoteSend()
[PASS] test_sendMessage()
[PASS] test_sendMessageReverse()
[PASS] test_sendEmptyMessage()

Test result: ok. 8 passed; 0 failed; 0 skipped
```

**SAVE THIS OUTPUT** — you'll paste it into the README.md later.

> DO NOT proceed to deployment until all tests pass.

---

## Phase 5: Deploy on Optimism Sepolia (L2-15)

```bash
forge script script/Deploy.s.sol --rpc-url optimism_sepolia --broadcast --verify
```

**Expected console output:**
```
CrossChainMessenger deployed at: 0x<OP_CONTRACT_ADDRESS>
Owner: 0x<YOUR_ADDRESS>
LZ Endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f
```

**Record:**
```
Optimism Sepolia Contract: ___________________________________
Optimism Deploy TX Hash: ___________________________________
```

If verification fails, manually verify later:
```bash
forge verify-contract <OP_CONTRACT_ADDRESS> src/CrossChainMessenger.sol:CrossChainMessenger --rpc-url optimism_sepolia --constructor-args $(cast abi-encode "constructor(address,address)" 0x6EDCE65403992e310A62460808c4b910D972f10f <YOUR_ADDRESS>)
```

---

## Phase 6: Deploy on Arbitrum Sepolia (L2-15)

```bash
forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --broadcast --verify
```

**Expected console output:**
```
CrossChainMessenger deployed at: 0x<ARB_CONTRACT_ADDRESS>
Owner: 0x<YOUR_ADDRESS>
LZ Endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f
```

**Record:**
```
Arbitrum Sepolia Contract: ___________________________________
Arbitrum Deploy TX Hash: ___________________________________
```

---

## Phase 7: Configure Trusted Peers (L2-13)

Both contracts must know about each other. This ensures only valid sources are accepted.

### 7.1 Set Peer on Optimism Sepolia (point to Arbitrum)

```bash
set MESSENGER_ADDRESS=<optimism_contract_address>
set REMOTE_EID=40231
set REMOTE_MESSENGER_ADDRESS=<arbitrum_contract_address>

forge script script/SetPeer.s.sol --rpc-url optimism_sepolia --broadcast
```

**Expected output:**
```
Peer set successfully!
Local contract: <optimism_contract_address>
Remote EID: 40231
Remote peer: <arbitrum_contract_address>
```

### 7.2 Set Peer on Arbitrum Sepolia (point to Optimism)

```bash
set MESSENGER_ADDRESS=<arbitrum_contract_address>
set REMOTE_EID=40232
set REMOTE_MESSENGER_ADDRESS=<optimism_contract_address>

forge script script/SetPeer.s.sol --rpc-url arbitrum_sepolia --broadcast
```

**Expected output:**
```
Peer set successfully!
Local contract: <arbitrum_contract_address>
Remote EID: 40232
Remote peer: <optimism_contract_address>
```

> BOTH peers must be configured before sending messages. If either fails, verify ETH balance and environment variables.

---

## Phase 8: Send a Cross-Chain Message (L2-12, L2-14)

### 8.1 Send Message from Optimism to Arbitrum

```bash
set MESSENGER_ADDRESS=<optimism_contract_address>
set DST_EID=40231
set MESSAGE=Hello Arbitrum from Optimism!

forge script script/SendMessage.s.sol --rpc-url optimism_sepolia --broadcast
```

**Expected output:**
```
Estimated native fee: <fee_in_wei>
Message sent successfully!
Destination EID: 40231
Message: Hello Arbitrum from Optimism!
```

**Record the SendMessage TX hash.**

### 8.2 Wait for LayerZero Relay

LayerZero takes approximately **2-5 minutes** to relay the message cross-chain.

You can monitor the message status at: https://testnet.layerzeroscan.com/

### 8.3 Verify Message Receipt on Arbitrum

After waiting 2-5 minutes:

```bash
cast call <arbitrum_contract_address> "lastMessage()(string)" --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

**Expected output:**
```
"Hello Arbitrum from Optimism!"
```

If the message matches what you sent, cross-chain messaging is working.

---

## Phase 9: Troubleshooting

### Deployment fails with "insufficient funds"
→ Get more testnet ETH from the respective faucet (Phase 1.2 or 1.3).

### SetPeer fails with "Ownable: caller is not the owner"
→ Ensure the PRIVATE_KEY in `.env` matches the address that deployed the contract.

### quoteSend returns 0 fee
→ Peers may not be set correctly. Verify with:
```bash
cast call <contract_address> "peers(uint32)(bytes32)" <remote_eid> --rpc-url <rpc_url>
```
The result should be non-zero (the remote contract address as bytes32).

### Message not received after 5+ minutes
1. Check LayerZero Scan: https://testnet.layerzeroscan.com/
2. Verify peers are set on BOTH chains
3. Ensure the destination chain contract has the source chain registered as a peer

### "EvmError: Revert" during SendMessage
→ Likely insufficient msg.value for the fee. The script uses quoteSend to estimate, but network conditions may change. Try increasing gas.

### forge build fails with "file not found"
→ Check `remappings.txt` and ensure `node_modules/` contains the LayerZero packages:
```bash
npm install
forge install foundry-rs/forge-std --no-commit
```

---

## Phase 10: Update Documentation (L2-16)

After all steps are complete, update the root `README.md`:

1. Replace `<OP_CONTRACT_ADDRESS>` with your Optimism Sepolia contract address
2. Replace `<ARB_CONTRACT_ADDRESS>` with your Arbitrum Sepolia contract address
3. Replace `<OP_TX_HASH>` with your Optimism deployment transaction hash
4. Replace `<ARB_TX_HASH>` with your Arbitrum deployment transaction hash
5. Replace `<PASTE TEST OUTPUT HERE>` with the full output of `forge test -vvv`

---

## LayerZero Reference Information

| Parameter | Optimism Sepolia | Arbitrum Sepolia |
|-----------|-----------------|-----------------|
| Endpoint ID (EID) | 40232 | 40231 |
| Endpoint Address | 0x6EDCE65403992e310A62460808c4b910D972f10f | 0x6EDCE65403992e310A62460808c4b910D972f10f |
| RPC URL | https://sepolia.optimism.io | https://sepolia-rollup.arbitrum.io/rpc |
| Explorer | https://sepolia-optimism.etherscan.io | https://sepolia.arbiscan.io |
| LZ Scan | https://testnet.layerzeroscan.com/ | https://testnet.layerzeroscan.com/ |

---

## Summary Checklist

- [ ] Node.js >= 18 installed
- [ ] Foundry installed (supports Solidity 0.8.24)
- [ ] Optimism Sepolia ETH obtained (non-zero balance confirmed)
- [ ] Arbitrum Sepolia ETH obtained (non-zero balance confirmed)
- [ ] `npm install` completed
- [ ] `forge install foundry-rs/forge-std --no-commit` completed
- [ ] `.env` configured with PRIVATE_KEY, RPC URLs, API keys
- [ ] `forge build` compiles successfully
- [ ] `forge test -vvv` — all tests passing (output saved)
- [ ] Deployed on Optimism Sepolia (address recorded)
- [ ] Deployed on Arbitrum Sepolia (address recorded)
- [ ] Peer configured on Optimism (pointing to Arbitrum, EID 40231)
- [ ] Peer configured on Arbitrum (pointing to Optimism, EID 40232)
- [ ] Cross-chain message sent from Optimism to Arbitrum
- [ ] Message receipt verified on Arbitrum (`lastMessage()` matches)
- [ ] README.md updated with all addresses, TX hashes, and test output
