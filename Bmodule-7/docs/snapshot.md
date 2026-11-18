# Snapshot Integration Guide

## Overview

The Participation DAO uses [Snapshot](https://snapshot.org) for off-chain signalling and
the on-chain `ParticipationGovernor` for binding execution. Voting power is read directly
from `ParticipationToken` which implements `IERC5805` (OpenZeppelin Votes interface).

---

## Token Compatibility

`ParticipationToken` is fully compatible with Snapshot because:

| Requirement | Implementation |
|-------------|---------------|
| `ERC20Votes` / `IERC5805` | ✅ Inherited via OZ ERC20Votes |
| `getVotes(address)` | ✅ Inherited |
| `getPastVotes(address, uint256)` | ✅ Inherited (block-number clock) |
| `getPastTotalSupply(uint256)` | ✅ Inherited |
| `delegate(address)` | ✅ Inherited |
| `delegateBySig(...)` | ✅ Inherited via ERC20Permit + ERC20Votes |
| `clock()` = block.number | ✅ Explicitly overridden |
| `CLOCK_MODE()` | ✅ Returns `"mode=blocknumber&from=default"` |

---

## Step-by-Step: Creating a Snapshot Space

### 1. Delegate Your Votes

Before any vote or proposal snapshot, token holders MUST delegate their votes.
Self-delegation is sufficient. New mints are auto-delegated, but calling `delegate()`
after transfers or to change delegation requires manual action.

```bash
# Using cast (Foundry):
cast send <TOKEN_ADDRESS> \
  "delegate(address)" <YOUR_ADDRESS> \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

Or use the Etherscan "Write Contract" tab → `delegate(delegatee)`.

### 2. Create a Snapshot Space

1. Go to [snapshot.org](https://snapshot.org) → "Create a Space"
2. Connect with an ENS-enabled wallet (or use a subdomain)
3. In **Strategies**, add:
   - **Strategy name**: `erc20-votes`
   - **Network**: Sepolia (chain ID `11155111`)
   - **Address**: `<ParticipationToken address>`
   - **Symbol**: `PART`
   - **Decimals**: `18`

### 3. Configure Validation

Use the `basic` validation strategy with `minScore = 5` (matching `proposalThreshold`).
This ensures only users with ≥ 5 PART can create Snapshot proposals (mirrors the on-chain rule).

### 4. Link the Governor

In the Space **Plugins** section:
- Add **SafeSnap** or **Governor** plugin
- Point to `ParticipationGovernor` address on Sepolia
- Timelock address: `<DAOTimelock address>`

---

## Delegation Flow

```
User earns PART via EarnerModule
         │
         ▼
   Auto-delegated to self on mint
         │
         ▼
  User can re-delegate:
    token.delegate(myAddress)        ← self-delegate (default)
    token.delegate(delegate)         ← delegate to representative
    token.delegateBySig(...)         ← gasless delegation via EIP-712 signature
         │
         ▼
  getVotes(delegate) increases
         │
         ▼
  Snapshot reads getPastVotes() at proposal snapshot block
```

---

## Testnet Deployment Info

> **Fill in after deployment**

| Contract | Address |
|----------|---------|
| `ParticipationToken` | `TBD` |
| `EarnerModule` | `TBD` |
| `Treasury` | `TBD` |
| `DAOTimelock` | `TBD` |
| `ParticipationGovernor` | `TBD` |
| Network | Sepolia (chain ID 11155111) |

### Snapshot Proposal

| Field | Value |
|-------|-------|
| Proposal URL | `TBD` |
| Execution TX | `TBD` |
| Treasury balance before | `TBD ETH` |
| Treasury balance after | `TBD ETH` |

---

## Security Notes

- **Non-transferable**: `PART` cannot be bought or sold. Delegation does NOT transfer tokens.
- **Delegation ≠ Transfer**: Delegating voting power does not move tokens. The token holder retains their balance and can re-delegate at any time.
- **Snapshot is advisory**: For binding execution, proposals must also pass through `ParticipationGovernor` on-chain. Snapshot proposals alone do not move funds.
