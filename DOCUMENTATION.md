# Game Economy — Documentation

## 1. Project Overview

A fully on-chain upgradeable game economy implemented as an ERC-1155 multi-token contract deployed behind a UUPS proxy.

| Token ID Range | Type | Description |
|---|---|---|
| `0` | Fungible | Currency token |
| `1 – 999` | Fungible | Material tokens |
| `>= 1000` | Non-fungible (supply 1) | Crafted unique items |

---

## 2. Proxy and Implementation Addresses

> Fill in after deployment. Run `npx hardhat run scripts/deploy.js --network <network>`.

| Contract | Address |
|---|---|
| **Proxy** | `0x6bB5E25EC2aA00451277ECDa142eF378a2D02021` |
| **ProxyAdmin** | `0x9704572a08341E0B7Ec0Aea86CD7192c14eB1669` |
| **V1 Implementation** | `0xdA3e33aCaf2f6C875DD4244B50F8eF7D4d798E06` |
| **V2 Implementation** | `0xBBE16049FCA082a02EcC09e5d96f765eab467a8f` |

Network: **Sepolia Testnet** (Chain ID: 11155111)

The proxy address is the canonical address for all user interactions. Implementation addresses change on upgrade; the proxy address stays constant.

---

## 3. Tools and Commands

### Dependencies
- **Hardhat** `^2.22.0` — development framework
- **@nomicfoundation/hardhat-toolbox** `^4.0.0` — testing, coverage, gas reports
- **@openzeppelin/hardhat-upgrades** `^3.0.0` — UUPS proxy deploy/upgrade
- **@openzeppelin/contracts-upgradeable** `^5.0.0` — ERC-1155, AccessControl, Pausable, UUPS base contracts

### Install
```bash
npm install
```

### Compile
```bash
npx hardhat compile
```

### Test
```bash
npx hardhat test
```

### Local Deploy
```bash
# Terminal 1 — start local node
npx hardhat node

# Terminal 2 — deploy V1 proxy
npx hardhat run scripts/deploy.js --network localhost

# Upgrade to V2 (reads proxy address from deployed-addresses.json)
npx hardhat run scripts/upgrade.js --network localhost
```

---

## 4. Currency Acquisition Model

**Model chosen: Fixed-price ETH sale**

```
buyCurrency(uint256 amount) payable
```

- Price: `0.001 ETH` per currency unit (`CURRENCY_PRICE` constant)
- User sends `amount × 0.001 ETH` → contract mints `amount` of token ID 0
- ETH is held in the contract; admin withdraws via `withdraw(to, amount)`
- Emits `CurrencyBought(buyer, amount, ethPaid)`

**Rationale:** A fixed price is simple, testable, and gas-predictable. No oracle or external price feed required. The faucet model was considered but the ETH sale creates real economic incentive and is easier to unit-test exact amounts.

---

## 5. Upgrade Design

### Pattern: EIP-1967 Transparent Upgradeable Proxy

- Proxy: ERC-1967 Transparent Proxy with dedicated ProxyAdmin contract
- Upgrade authorization: ProxyAdmin contract (deployed by OZ hardhat-upgrades plugin)
- Upgrade call: ProxyAdmin calls `upgradeAndCall()` on the proxy — only the admin can trigger upgrades
- Admin separation: The ProxyAdmin ensures that the implementation contract itself has no upgrade logic, reducing attack surface

### Why Transparent Proxy?

| | Transparent Proxy | UUPS |
|---|---|---|
| Upgrade logic location | External ProxyAdmin | Inside implementation |
| Admin attack surface | Separate contract, minimal | Implementation function |
| Upgrade forgotten risk | None (ProxyAdmin always exists) | Risk if `_authorizeUpgrade` missing in V2 |
| Gas cost per user call | Slightly higher (admin check) | Lower |
| OpenZeppelin support | Full, battle-tested | Full, recommended for gas savings |

**Chosen because**: The reviewer requested EIP-1967 Transparent Proxy. It provides clearer separation between admin operations and user operations, and eliminates the risk of a bricked proxy if an implementation upgrade forgets to include the upgrade function.

### Storage Layout — Collision Prevention

`GameEconomyV2` inherits `GameEconomyV1` directly. No new state variables are added before the inherited ones, so the storage layout is append-only. OpenZeppelin's `upgrades` plugin validates this automatically during `upgrades.upgradeProxy()`.

**V1 Storage Slots (simplified):**
```
slot 0–N  : OZ upgradeable base contract gaps (ERC1155, AccessControl, etc.)
slot last : nextUniqueId, materialPrice, recipe, recipeMaterialIds
```

**V2 additions:** Only new functions, no new state variables → zero risk of storage collision.

---

## 6. Testnet Deployment (Sepolia)

### Setup
```bash
cp .env.example .env
# Edit .env with your PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY
```

### Deploy & Upgrade on Sepolia
```bash
npx hardhat run scripts/deploy.js --network sepolia
npx hardhat run scripts/upgrade.js --network sepolia
```

### Verify on Etherscan
```bash
npx hardhat verify --network sepolia <IMPLEMENTATION_ADDRESS>
```

### Deployed Addresses (Sepolia)

| Contract | Address | Etherscan Link |
|---|---|---|
| **Proxy** | `0x6bB5E25EC2aA00451277ECDa142eF378a2D02021` | https://sepolia.etherscan.io/address/0x6bB5E25EC2aA00451277ECDa142eF378a2D02021 |
| **ProxyAdmin** | `0x9704572a08341E0B7Ec0Aea86CD7192c14eB1669` | https://sepolia.etherscan.io/address/0x9704572a08341E0B7Ec0Aea86CD7192c14eB1669 |
| **V1 Implementation** | `0xdA3e33aCaf2f6C875DD4244B50F8eF7D4d798E06` | https://sepolia.etherscan.io/address/0xdA3e33aCaf2f6C875DD4244B50F8eF7D4d798E06#code |
| **V2 Implementation** | `0xBBE16049FCA082a02EcC09e5d96f765eab467a8f` | https://sepolia.etherscan.io/address/0xBBE16049FCA082a02EcC09e5d96f765eab467a8f#code |

---

## 6. Security Choices

### Checks-Effects-Interactions (CEI)

Every value-flow function follows CEI:
1. **Check** all preconditions (balance, role, pause state)
2. **Effect** state changes (burn tokens, increment counter)
3. **Interact** with external calls last (mint, ETH transfer)

Example — `buyMaterial`:
```solidity
// Check
require(balanceOf(msg.sender, CURRENCY_ID) >= totalCost, ...);

// Effect (burn first — CEI)
_burn(msg.sender, CURRENCY_ID, totalCost);

// Interact (internal only — no external call)
_mint(msg.sender, id, amount, "");
```

### ReentrancyGuard

Applied to `withdraw()` — the only function that makes an external ETH `.call{value}()`. All other functions only call internal `_mint`/`_burn` with no external re-entry surface.

### No `tx.origin`

All authentication uses `msg.sender` exclusively.

### No Unbounded Loops in State-Changing Paths

- **`craft()`** loops over `recipeMaterialIds` — bounded by the admin-set recipe length (a small, fixed list, e.g., 2–10 materials)
- **`setRecipe()`** loops over the new recipe array — admin-only, not a user-facing state change path
- **`buyMaterialsBatch()`** (V2) loops over caller-supplied arrays — bounded by the input length; gas cost is proportional to the number of materials, which is the caller's choice

### Pausable

All three user-facing operations (`buyCurrency`, `buyMaterial`, `craft`) and admin `withdraw` check `whenNotPaused`. The `PAUSER_ROLE` can pause/unpause independently of the admin.

### Role Separation

| Role | Actions |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Grant/revoke all roles |
| `PAUSER_ROLE` | `pause()`, `unpause()` |
| `GAME_ADMIN_ROLE` | `setMaterialPrice()`, `setRecipe()`, `withdraw()` |
| **ProxyAdmin** (external contract) | `upgradeAndCall()` on the proxy |

---

## 7. CTF Challenges

### Ethernaut 6 — Delegation

**File:** `contracts/ctf/Delegation.sol`  
**Test:** `test/ctf/Delegation.test.js`

**Vulnerability:** `Delegation.fallback()` blindly `delegatecall`s into `Delegate` with `msg.data`. Sending the `pwn()` selector causes `Delegate.pwn()` to execute in `Delegation`'s storage context, overwriting `Delegation.owner` (slot 0).

**Exploit:**
```
delegation.call(abi.encodeWithSignature("pwn()"))
```

**Fix:** Never use `delegatecall` in a fallback without strict selector whitelisting and access control.

---

### Ethernaut 16 — Preservation

**File:** `contracts/ctf/Preservation.sol`  
**Test:** `test/ctf/Preservation.test.js`

**Vulnerability:** `Preservation` `delegatecall`s `LibraryContract.setTime()`. `LibraryContract` stores data in slot 0 (its `storedTime`), but `Preservation`'s slot 0 is `timeZone1Library`. The delegatecall overwrites the library address with attacker-supplied data.

**Two-step exploit:**
1. `setFirstTime(uint(maliciousLibraryAddress))` → overwrites `timeZone1Library` with attacker's library
2. `setFirstTime(0)` → now delegatecalls attacker's library, which writes `msg.sender` to slot 2 (`owner`)

**Fix:** Ensure the delegatecalled library has an identical storage layout to the calling contract. Use abstract base contracts with shared layout.

---

### Ethernaut 24 — Puzzle Wallet

**File:** `contracts/ctf/PuzzleWallet.sol`  
**Test:** `test/ctf/PuzzleWallet.test.js`

**Vulnerability:** Two separate bugs chain together:
1. **Storage collision:** `PuzzleProxy.pendingAdmin` (slot 0) collides with `PuzzleWallet.owner` (slot 0). Calling `proxy.proposeNewAdmin(attacker)` sets `wallet.owner = attacker`.
2. **`msg.value` re-use in `multicall`:** The `depositCalled` guard only prevents double direct `deposit()` calls, but a `multicall` nested inside `multicall` resets the flag, allowing `msg.value` to be credited multiple times.

**Five-step exploit:**
1. `proposeNewAdmin(attacker)` → becomes wallet owner
2. `addToWhitelist(attacker)` → whitelist self
3. `multicall([deposit, multicall([deposit])])` with 0.001 ETH → balances[attacker] = 0.002
4. `execute(attacker, 0.002)` → drain all ETH
5. `setMaxBalance(uint(attacker))` → slot 1 collision sets proxy admin to attacker

**Fix:** Proxy and implementation must never have overlapping state variable slots. Use OpenZeppelin's `ERC1967` or `TransparentUpgradeableProxy` which stores admin in a dedicated EIP-1967 slot. Never allow `msg.value` forwarding through `delegatecall` in `multicall` patterns.

---

## 8. Test Coverage Summary

| Test Group | Tests |
|---|---|
| Initialization | 3 |
| buyCurrency | 6 |
| withdraw | 5 |
| setMaterialPrice | 5 |
| buyMaterial | 5 |
| setRecipe | 5 |
| craft | 6 |
| Pause Control | 7 |
| V2 Upgrade — state + features | 12 |
| End-to-end flow | 1 |
| CTF: Delegation | 4 |
| CTF: Preservation | 5 |
| CTF: Puzzle Wallet | 6 |
| **Total** | **~70** |
