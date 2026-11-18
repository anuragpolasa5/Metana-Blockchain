# Module 8 — Demo Report
### Upgradeable ERC-1155 Game Economy + Ethernaut CTF Challenges

**Author:** Anurag · **Network:** Sepolia Testnet (Chain ID 11155111) · **Date:** 2026-06-15

---

## 1. Executive Summary (30-second pitch)

I built a fully on-chain, **upgradeable game economy** as a single ERC-1155 contract sitting
behind an **EIP-1967 Transparent Proxy**. One contract handles three asset classes:

| Token ID range | Type | Role in the economy |
|---|---|---|
| `0` | Fungible | In-game currency (bought with ETH at a fixed price) |
| `1 – 999` | Fungible | Crafting materials (bought with currency) |
| `>= 1000` | Non-fungible (supply 1) | Unique crafted items |

I then **upgraded it from V1 → V2 live on Sepolia**, proving that all user balances,
prices, and recipes survived the upgrade — which is the whole point of the proxy pattern.

Alongside the economy I solved and unit-tested **three Ethernaut CTF challenges**
(Delegation #6, Preservation #16, Puzzle Wallet #24), all of which exploit the same
underlying theme this module is about: **`delegatecall` and proxy storage layout**.

**Result: 74/74 tests passing, V1 + V2 deployed and verified on Sepolia Etherscan.**

---

## 2. Live Deployment (Sepolia) — the proof

All four addresses are real and verifiable on Etherscan right now.

| Contract | Address | Etherscan |
|---|---|---|
| **Proxy** (canonical user address) | `0x6bB5E25EC2aA00451277ECDa142eF378a2D02021` | [view](https://sepolia.etherscan.io/address/0x6bB5E25EC2aA00451277ECDa142eF378a2D02021) |
| **ProxyAdmin** | `0x9704572a08341E0B7Ec0Aea86CD7192c14eB1669` | [view](https://sepolia.etherscan.io/address/0x9704572a08341E0B7Ec0Aea86CD7192c14eB1669) |
| **V1 Implementation** | `0xdA3e33aCaf2f6C875DD4244B50F8eF7D4d798E06` | [code](https://sepolia.etherscan.io/address/0xdA3e33aCaf2f6C875DD4244B50F8eF7D4d798E06#code) |
| **V2 Implementation** | `0xBBE16049FCA082a02EcC09e5d96f765eab467a8f` | [code](https://sepolia.etherscan.io/address/0xBBE16049FCA082a02EcC09e5d96f765eab467a8f#code) |

> **Demo talking point:** The proxy address never changes. Users always interact with the
> proxy. When I upgraded, only the *implementation* pointer flipped from V1 → V2 — the
> proxy and all its storage stayed identical. This is confirmed in the
> `.openzeppelin/sepolia.json` manifest, which records both implementations behind the one proxy.

---

## 3. Architecture & Design Decisions

### 3.1 Why the Transparent Proxy (EIP-1967)
Upgrade authorization lives in a **separate ProxyAdmin contract**, not inside the
implementation. Admin calls (upgrade) are intercepted by the proxy; every other call is
delegated to the implementation.

- **Benefit:** clean separation of admin vs. user logic, and no risk of "bricking" the
  proxy if a future implementation forgets to include upgrade logic.
- **Storage safety:** `GameEconomyV2` *inherits* `GameEconomyV1` and adds **only new
  functions — zero new state variables**. The storage layout is therefore append-only and
  cannot collide. OpenZeppelin's `hardhat-upgrades` plugin validates this automatically on
  upgrade.

### 3.2 Currency acquisition model
**Fixed-price ETH sale** — `buyCurrency(amount)` mints token ID 0 for
`amount × 0.001 ETH`. Chosen over a faucet because it creates real economic incentive and
makes exact-amount unit testing straightforward. ETH accumulates in the contract; admin
pulls it via `withdraw(to, amount)`.

### 3.3 Role separation (principle of least privilege)
| Role | Powers |
|---|---|
| `DEFAULT_ADMIN_ROLE` | grant/revoke roles |
| `PAUSER_ROLE` | `pause()` / `unpause()` |
| `GAME_ADMIN_ROLE` | `setMaterialPrice`, `setRecipe`, `withdraw` |
| **ProxyAdmin** (external) | `upgradeAndCall()` on the proxy |

### 3.4 V2 upgrade feature
`buyMaterialsBatch(ids[], amounts[])` — buy multiple materials in one transaction with a
**single currency burn**, saving gas vs. repeated `buyMaterial` calls. Plus a
`version()` function returning `"V2"` used to confirm the upgrade took effect.

---

## 4. Security Hardening (what I'd point to in a review)

- **Checks-Effects-Interactions** everywhere value flows — e.g. `buyMaterial` and `craft`
  **burn before mint**, so state is settled before any token movement.
- **ReentrancyGuard** on `withdraw()` — the only function that makes an external
  `.call{value}` ETH transfer.
- **No `tx.origin`** — all auth uses `msg.sender`.
- **No unbounded loops in user state-changing paths** — the only loops iterate
  admin-set recipe arrays (small, fixed) or caller-supplied batch arrays (caller pays the gas).
- **Pausable** guards all three user operations + withdraw.
- **Zero-address checks** on `initialize` admin and `withdraw` recipient (added per PR review).
- **`_disableInitializers()`** in the constructor so the implementation can't be
  initialized directly, only through the proxy.

---

## 5. CTF Findings — the security lessons

All three challenges revolve around `delegatecall` and storage layout, which directly
reinforces why the proxy in Part 1 had to be built so carefully.

### Ethernaut #6 — Delegation
- **Bug:** `fallback()` blindly `delegatecall`s `msg.data` into a `Delegate` contract.
- **Exploit:** call the proxy with the `pwn()` selector → `Delegate.pwn()` runs in
  *Delegation's* storage and overwrites `owner` (slot 0).
- **Lesson:** never `delegatecall` arbitrary `msg.data` in a fallback without selector
  whitelisting.

### Ethernaut #16 — Preservation
- **Bug:** `Preservation` delegatecalls a library that writes slot 0. The library's slot 0
  is `storedTime`, but Preservation's slot 0 is the library *address*.
- **Exploit (2 steps):** first call overwrites the library pointer with an attacker
  library; second call delegatecalls the attacker library, which writes `msg.sender` into
  the `owner` slot.
- **Lesson:** a delegatecalled library **must mirror the caller's storage layout exactly**.

### Ethernaut #24 — Puzzle Wallet
- **Bug (chained):** (1) `PuzzleProxy.pendingAdmin` collides with `PuzzleWallet.owner`
  (both slot 0); (2) `multicall` nested inside `multicall` lets the same `msg.value` be
  credited twice.
- **Exploit:** propose self as admin → whitelist self → double-count a deposit via nested
  multicall → drain the wallet → `setMaxBalance` overwrites the proxy admin slot.
- **Lesson:** this is the textbook argument for **EIP-1967 dedicated storage slots** —
  exactly what the Part 1 proxy uses, so it can't happen there.

---

## 6. Testing

**74/74 tests pass** for the Module 8 scope (and 139/139 across the whole repo) with a
plain `npx hardhat test` — see §7 for the config fix that made this work with no flags:

| Suite | Tests | Focus |
|---|---|---|
| GameEconomy V1 (GE-1…GE-9) | 46 | init, buyCurrency, withdraw, pricing, buyMaterial, recipes, craft, pause |
| GameEconomy V2 upgrade (GE-10) | 12 | state preservation across upgrade + batch buy + version |
| CTF: Delegation / Preservation / Puzzle Wallet | 16 | each exploit step + full chain |
| **Total** | **74** | |

Every requirement ID (`GE-1`…`GE-10`) is tagged as a comment in the Solidity source at the
exact function that fulfills it, giving full requirement traceability.

**Edge cases deliberately covered:** zero amounts, exact-ETH matching (both under- and
over-payment revert), boundary IDs (0 and 1000 rejected as materials), unpriced materials,
successive crafts getting unique incrementing IDs, and all V1 functions still working
post-upgrade.

---

## 7. ✅ Resolved: Test Configuration (history)

The repo contains **two Hardhat config files** — `hardhat.config.js` and the default
`hardhat.config.cjs` (originally from an earlier escrow module). The `.cjs` config was
**missing** the `@openzeppelin/hardhat-upgrades` plugin, so a cold `npx hardhat test`
loaded it and failed the GameEconomy proxy suite with
`Cannot read properties of undefined (reading 'deployProxy')`.

**Fixed:** `require("@openzeppelin/hardhat-upgrades");` was added to `hardhat.config.cjs`.
A bare `npx hardhat test` now runs the whole repo green with **no flags required** — no
`--config` workaround needed. While in this area I also fixed two stale EscrowSuite
assertions that called removed boolean getters (`funded()` / `released()`); they now check
the `EscrowState` enum via `state()`.

> **Current state:** `npx hardhat test` → **139 passing, 0 failing** (74 of which are the
> Module 8 GameEconomy + CTF scope). Safe to run cold in front of your instructor.

---

## 8. Live Demo Script (suggested 5-minute flow)

1. **Open the Sepolia proxy on Etherscan** → show it's a live, verified contract (§2).
2. **Show V1 vs V2 implementation addresses** → "same proxy, two implementations = upgrade worked."
3. **Run the tests:** `npx hardhat test` → 139 passing (74 in the Module 8 scope).
4. **Walk one CEI function** (`buyMaterial` in `contracts/GameEconomyV1.sol`) → burn-before-mint.
5. **Walk the V2 upgrade test** → balances/prices/recipes preserved after `upgradeProxy`.
6. **Pick one CTF** (Puzzle Wallet is the most impressive) → explain the storage-collision
   chain, then tie it back: "this is why my proxy uses EIP-1967 slots."

---

## 9. Repository Map

```
contracts/
  GameEconomyV1.sol     # core economy (GE-1…GE-9), NatSpec + requirement tags
  GameEconomyV2.sol     # upgrade: buyMaterialsBatch + version()
  ctf/
    Delegation.sol      # Ethernaut #6
    Preservation.sol    # Ethernaut #16
    PuzzleWallet.sol    # Ethernaut #24
scripts/
  deploy.js             # deploy V1 proxy
  upgrade.js            # upgrade proxy to V2
test/
  GameEconomy.test.js   # 58 tests
  ctf/*.test.js         # 16 tests
.openzeppelin/sepolia.json   # proxy + impl manifest (proof of deployment)
deployed-addresses.json      # the 4 live addresses
DOCUMENTATION.md / README.md # full writeup
```
```
```
