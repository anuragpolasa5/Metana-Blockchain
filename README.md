# Module 8 — Upgradeable ERC-1155 Game Economy + CTF Challenges

## What I Learned

This module deepened my understanding of several advanced Solidity concepts:

**EIP-1967 Transparent Proxy Pattern**: I learned how the Transparent Proxy pattern works — the ProxyAdmin contract handles upgrade authorization separately from the implementation, which provides cleaner separation of concerns. Admin calls (upgrade) are intercepted by the proxy itself, while all other calls are delegated to the implementation. The key insight is that the proxy's storage layout must remain append-only across versions to avoid slot collisions.

**ERC-1155 Multi-Token Design**: Using a single contract for fungible currency (ID 0), fungible materials (IDs 1–999), and non-fungible crafted items (IDs >= 1000) taught me how flexible ERC-1155 is for game economies. The `_mint` and `_burn` functions handle all token types uniformly.

**Storage Layout in Upgradeable Contracts**: V2 inherits V1 directly and adds NO new state variables — only new functions. This guarantees zero storage collision risk. OpenZeppelin's `hardhat-upgrades` plugin validates this automatically.

**CEI (Checks-Effects-Interactions) Pattern**: I internalized why burn-before-mint ordering matters. Even though `_mint` and `_burn` are internal calls (not external interactions), following CEI consistently prevents subtle reentrancy issues if the contract ever interacts with ERC1155 receiver hooks.

**CTF Security Lessons**:
- **Delegation (Ethernaut 6)**: Never use `delegatecall` in a fallback without strict selector whitelisting. The caller controls `msg.data` and thus which function runs in your storage context.
- **Preservation (Ethernaut 16)**: Storage layout mismatches between caller and callee in a delegatecall are catastrophic. Libraries must mirror the caller's layout exactly.
- **Puzzle Wallet (Ethernaut 24)**: Proxy storage collisions (pendingAdmin ↔ owner, admin ↔ maxBalance) combined with `msg.value` reuse in nested multicalls create a chain of exploits. This is exactly why EIP-1967 storage slots exist.

---

## Problems & Solutions

### Problem 1: `ReentrancyGuardUpgradeable` Not Found (Compilation Failure)

**Issue**: The project initially used `@openzeppelin/contracts-upgradeable@^5.0.0` which resolved to v5.6.1. In that version, `ReentrancyGuardUpgradeable` was removed from the package (it was consolidated since ReentrancyGuard uses transient storage and doesn't need initialization in newer versions).

**Solution**: Pinned `@openzeppelin/contracts-upgradeable` to exactly `5.0.2` which still includes the upgradeable ReentrancyGuard. This was a deliberate tradeoff — using a slightly older but stable version that provides all the imports the contract architecture requires. In `package.json`:
```json
"@openzeppelin/contracts-upgradeable": "5.0.2"
```

### Problem 2: PuzzleWallet Proxy Init Failing

**Issue**: The `PuzzleProxy` constructor accepted ETH via `{ value: ... }` in the deploy call, but then delegatecalled `PuzzleWallet.init()` which is a `non-payable` function. In Solidity 0.8+, non-payable functions have an implicit `require(msg.value == 0)` check compiled into their bytecode. Since `delegatecall` preserves `msg.value` from the calling context, the init function saw `msg.value > 0` and reverted.

**Solution**: Two changes:
1. Reordered the constructor to set `implementation` before the delegatecall, and `admin` after it (avoiding slot collision during init).
2. In the test, ETH is sent to the proxy in a separate transaction AFTER deployment, rather than in the constructor call. This matches how the actual Ethernaut challenge works on-chain.

### Problem 3: No Common Git History for PR

**Issue**: The local repo was initialized fresh with `git init`, so pushing to a remote that already had a `main` branch resulted in "no history in common" when trying to create a PR.

**Solution**: Fetched `origin/main` and rebased the branch onto it, establishing common ancestry before force-pushing.

---

## Testing Approach

### Strategy

The test suite follows a **requirement-driven** approach — each test group maps directly to a specification requirement ID (GE-1 through GE-10), plus CTF exploit demonstrations.

### What's Covered (74 tests total)

| Test Group | Tests | Focus |
|---|---|---|
| Initialization (GE-1) | 3 | Proxy init, role grants, re-init prevention |
| buyCurrency (GE-3) | 6 | Happy path, exact ETH matching, under/overpayment, zero amount, ETH accumulation |
| withdraw (GE-4) | 5 | Admin withdrawal, access control, insufficient balance, zero address |
| setMaterialPrice (GE-5) | 5 | Price setting, events, access control, boundary validation (ID 0, ID >= 1000) |
| buyMaterial (GE-6) | 5 | Currency burn + material mint, insufficient funds, unpriced material, zero amount |
| setRecipe (GE-7) | 6 | Recipe storage, replacement, events, length mismatch, empty recipe, access control |
| craft (GE-8) | 6 | Material burn + unique mint, ID increment, successive crafts, insufficient materials, no recipe |
| Pause Control (GE-2) | 7 | Pause/unpause, blocks all operations, non-pauser rejection, resume after unpause |
| V2 Upgrade (GE-10) | 12 | State preservation (balances, prices, recipes, nextUniqueId), batch purchase, version check, pause integration, access control |
| End-to-end | 1 | Full happy path: buy currency → buy materials → craft |
| CTF: Delegation | 4 | Initial state, contract exploit, EOA exploit, re-exploitation |
| CTF: Preservation | 5 | Initial state, step-by-step slot collision, full exploit via attacker contract |
| CTF: Puzzle Wallet | 7 | Initial state, each exploit step individually, full chain exploit |

### Edge Cases Deliberately Tested

- **Zero amounts** in buyCurrency, buyMaterial — ensures revert on meaningless operations
- **Exact ETH matching** — both underpayment AND overpayment revert (no refund logic)
- **Boundary IDs** — ID 0 (currency) and ID 1000 (crafted start) cannot be used as materials
- **Unpriced materials** — buying a material with no price set reverts
- **Successive crafts** — verifies each craft gets a unique, incrementing ID
- **Post-upgrade operations** — V1 functions (craft, buy) still work identically after V2 upgrade
- **Pause blocking V2 features** — buyMaterialsBatch respects pause state
- **Non-UPGRADER attempting upgrade** — access control on UUPS authorization

### What's NOT Tested (and Why)

- **Gas limits / block gas overflow**: The recipe loop is bounded by admin input (typically 2–5 materials). Testing gas limits would require artificially large arrays that no real admin would set.
- **Reentrancy attacks on withdraw**: The `nonReentrant` modifier is from a battle-tested OpenZeppelin library. Testing the modifier itself would be testing OZ, not our contract logic.
- **ERC-1155 receiver hooks**: Our contract doesn't interact with external ERC-1155 receivers in any user path. All mints go to EOAs in tests.
- **Fuzz testing**: While property-based tests would add coverage, the deterministic unit tests already cover all requirement IDs and edge cases specified.

---

## Requirement Traceability

All requirement IDs are tagged as comments directly in the Solidity source code at the exact location where they are fulfilled:

- **GE-1** → `GameEconomyV1.sol` `initialize()` function
- **GE-2** → `GameEconomyV1.sol` `pause()` / `unpause()` section
- **GE-3** → `GameEconomyV1.sol` `buyCurrency()` function
- **GE-4** → `GameEconomyV1.sol` `withdraw()` function
- **GE-5** → `GameEconomyV1.sol` `setMaterialPrice()` function
- **GE-6** → `GameEconomyV1.sol` `buyMaterial()` function
- **GE-7** → `GameEconomyV1.sol` `setRecipe()` function
- **GE-8** → `GameEconomyV1.sol` `craft()` function
- **GE-9** → `GameEconomyV1.sol` `_authorizeUpgrade()` section + CEI throughout
- **GE-10** → `GameEconomyV2.sol` `buyMaterialsBatch()` function
