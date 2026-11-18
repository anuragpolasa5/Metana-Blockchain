# Part B - Cairo Simple Storage: Complete Deployment Guide

## Requirement Coverage
| ID | Behaviour | Status |
|----|-----------|--------|
| L2-5 | Cairo 1.0 contract with set/get felt252 | `src/lib.cairo` |
| L2-6 | Decorators: #[storage], #[external], #[view] | `src/lib.cairo` |
| L2-7 | Comments explaining each function | `src/lib.cairo` |
| L2-8 | Compile and deploy using starkli/sncast | Steps below |
| L2-9 | Deployed contract address and TX hash documented | Phase 5 |
| L2-10 | Unit tests using snforge | `tests/test_simple_storage.cairo` |

---

## Phase 0: Toolchain Verification

Before starting, confirm these tools are installed and meet minimum versions:

```bash
scarb --version       # Must support Cairo edition 2024_07 (Scarb >= 2.9.x)
snforge --version     # Must be starknet-foundry v0.34.0
starkli --version     # Must support Starknet Sepolia
```

### Install Scarb (if not installed)
```bash
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
```
Or on Windows, download from: https://docs.swmansion.com/scarb/download.html

### Install Starknet Foundry (snforge + sncast)
```bash
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
snfoundryup -v 0.34.0
```

### Install starkli
```bash
curl https://get.starkli.sh | sh
starkliup
```

If any version is below the minimum, upgrade before proceeding.

---

## Phase 1: Starknet Wallet Setup and Testnet ETH

### 1.1 Create a Starknet Account (if you don't have one)

**Option A: Using starkli (recommended for CLI deployment)**

```bash
# Create a keystore (you'll be prompted for a password)
starkli signer keystore from-key ~/.starkli-wallets/deployer/keystore.json

# Create an account descriptor
starkli account oz init ~/.starkli-wallets/deployer/account.json
```

**Option B: Using Argent or Braavos wallet**
1. Install Argent X or Braavos browser extension
2. Create a new wallet on Starknet Sepolia
3. Export the account details for starkli

### 1.2 Get Starknet Sepolia ETH

1. Visit: https://starknet-faucet.vercel.app/
2. Enter your Starknet Sepolia wallet address
3. Request testnet ETH

### 1.3 Deploy Your Account (first time only)

```bash
export STARKNET_RPC=https://starknet-sepolia.public.blastapi.io
export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/account.json
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/keystore.json

# Deploy the account contract
starkli account deploy ~/.starkli-wallets/deployer/account.json
```

### 1.4 Verify Balance

```bash
starkli balance <YOUR_STARKNET_ADDRESS> --rpc https://starknet-sepolia.public.blastapi.io
```

> DO NOT proceed until you confirm a non-zero ETH balance on Starknet Sepolia.

---

## Phase 2: Build the Contract (L2-5, L2-6, L2-7)

```bash
cd partB-cairo-storage
scarb build
```

**Expected output:**
```
Compiling simple_storage v0.1.0
Finished `dev` profile target(s) in X seconds
```

This produces:
- `target/dev/simple_storage_SimpleStorage.contract_class.json` (Sierra artifact)
- `target/dev/simple_storage_SimpleStorage.compiled_contract_class.json` (CASM artifact)

**If build fails:**
1. Verify Scarb is installed: `scarb --version`
2. Check that `Scarb.toml` dependencies are correct
3. Run `scarb clean` then `scarb build`

---

## Phase 3: Run Unit Tests (L2-10)

```bash
snforge test
```

**Expected output (5 passing tests):**
```
Collected 5 test(s) from simple_storage package
Running 5 test(s) from tests/
[PASS] test_simple_storage::test_initial_value_is_zero (gas: ~XXX)
[PASS] test_simple_storage::test_set_value (gas: ~XXX)
[PASS] test_simple_storage::test_overwrite_value (gas: ~XXX)
[PASS] test_simple_storage::test_set_zero (gas: ~XXX)
[PASS] test_simple_storage::test_large_value (gas: ~XXX)
Tests: 5 passed, 0 failed, 0 skipped, 0 ignored
```

**If any test fails:**
1. Review the test output for the specific assertion that failed
2. Verify `src/lib.cairo` matches the expected interface (ISimpleStorage with set/get)
3. Run `scarb clean && scarb build` then re-run tests

> DO NOT proceed to deployment until all 5 tests pass.

---

## Phase 4: Declare and Deploy on Starknet Sepolia (L2-8)

### 4.1 Set Environment Variables

```bash
export STARKNET_RPC=https://starknet-sepolia.public.blastapi.io
export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/account.json
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/keystore.json
```

### 4.2 Declare the Contract Class

```bash
starkli declare target/dev/simple_storage_SimpleStorage.contract_class.json
```

**Expected output:**
```
Declaring Cairo 1 class: 0x<CLASS_HASH>
Transaction hash: 0x<DECLARE_TX_HASH>
Class hash declared: 0x<CLASS_HASH>
```

**Record the class hash:**
```
Class Hash: ___________________________________
Declare TX: ___________________________________
```

**If declaration fails with "class already declared":**
- This is OK. Use the existing class hash from the error message and proceed to deployment.

### 4.3 Deploy the Contract

```bash
starkli deploy <CLASS_HASH>
```

No constructor arguments are needed (the contract has no constructor).

**Expected output:**
```
Deploying class 0x<CLASS_HASH>...
Transaction hash: 0x<DEPLOY_TX_HASH>
Contract deployed: 0x<CONTRACT_ADDRESS>
```

**Record these values:**
```
Contract Address: ___________________________________
Deploy TX Hash: ___________________________________
Explorer: https://sepolia.starkscan.co/contract/<CONTRACT_ADDRESS>
```

### Alternative: Using sncast

```bash
# Declare
sncast --account myaccount declare --contract-name SimpleStorage

# Deploy
sncast --account myaccount deploy --class-hash <CLASS_HASH>
```

---

## Phase 5: Verify Deployment (L2-9)

### 5.1 Call the `get` function to verify initial state

```bash
starkli call <CONTRACT_ADDRESS> get --rpc https://starknet-sepolia.public.blastapi.io
```

**Expected output:**
```
[
    "0x0"
]
```

This confirms the contract is deployed and the initial stored value is 0.

### 5.2 Test the `set` function

```bash
starkli invoke <CONTRACT_ADDRESS> set 42
```

### 5.3 Verify the value was stored

```bash
starkli call <CONTRACT_ADDRESS> get --rpc https://starknet-sepolia.public.blastapi.io
```

**Expected output:**
```
[
    "0x2a"
]
```

(0x2a = 42 in hexadecimal)

### 5.4 View on Explorer

Open: https://sepolia.starkscan.co/contract/<CONTRACT_ADDRESS>

---

## Phase 6: Troubleshooting

### "Account not deployed" error
→ Run `starkli account deploy` first (Phase 1.3)

### "Insufficient balance" error
→ Get more testnet ETH from https://starknet-faucet.vercel.app/

### "Class hash not found" error during deploy
→ The declare transaction may not be confirmed yet. Wait 30 seconds and retry.

### "Invalid transaction nonce" error
→ Wait for pending transactions to confirm, then retry.

### Build fails with "unresolved dependency"
→ Check internet connection. Run `scarb clean` then `scarb build`.

---

## Phase 7: Update Documentation (L2-9)

After successful deployment, update the root `README.md`:
1. Replace `<DEPLOYED_CONTRACT_ADDRESS>` in Part B section with your actual Starknet contract address
2. Replace `<DEPLOYMENT_TX_HASH>` with your actual deployment transaction hash
3. Add the class hash to your records

---

## Summary Checklist

- [ ] Scarb installed (compatible with Cairo edition 2024_07)
- [ ] snforge v0.34.0 installed
- [ ] starkli installed and configured
- [ ] Starknet Sepolia account created and deployed
- [ ] Testnet ETH obtained from faucet
- [ ] `scarb build` completed successfully
- [ ] `snforge test` — all 5 tests passing
- [ ] Contract class declared (class hash recorded)
- [ ] Contract deployed (address recorded)
- [ ] `get` function returns `0x0` (verified)
- [ ] `set` and `get` tested with value 42
- [ ] README.md updated with deployment details

---

## Contract Architecture Reference

```
ISimpleStorage (Interface - #[starknet::interface])
├── set(ref self, value: felt252)   → External: writes value to storage
└── get(self) -> felt252            → View: reads value from storage

SimpleStorage (Contract - #[starknet::contract])
├── #[storage]
│   └── Storage { stored_value: felt252 }
└── #[abi(embed_v0)] SimpleStorageImpl
    ├── set() → self.stored_value.write(value)
    └── get() → self.stored_value.read()
```
