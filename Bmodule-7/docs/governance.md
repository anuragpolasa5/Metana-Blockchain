# Participation DAO – Governance Parameter Justification

## Overview

The Participation DAO replaces token-wealth-based voting with **earned participation weight**.
Users accumulate `PART` tokens by performing on-chain actions, not by purchasing tokens.

---

## Epoch Configuration

| Parameter | Value | Justification |
|-----------|-------|---------------|
| `EPOCH_DURATION` | 7 days | Weekly cadence matches most DAO tooling (Snapshot, Tally). Long enough to be Sybil-resistant (cost per identity action = 1 week), short enough to stay responsive. |

---

## Earning Caps

| Cap | Value | Justification |
|-----|-------|---------------|
| Check-in reward | 1 PART / epoch | Sybil-resistant: one meaningful identity action per week. Low enough to not dominate total supply. |
| User funding cap | 10 PART / epoch | Whales can contribute ≥ 0.1 ETH and earn the max, but cannot earn more to prevent vote buying. |
| Global funding cap | 100 PART / epoch | Bounds weekly inflation to ≤ 100 PART from funders. Combined with check-in supply, total weekly issuance is bounded. |
| Funding rate | 100 PART / ETH | 0.01 ETH = 1 PART, making the check-in and minimum fund contribution comparable in value. |

---

## Governor Parameters

| Parameter | Value | Block Equivalent | Justification |
|-----------|-------|-----------------|---------------|
| `votingDelay` | 7,200 blocks | ≈ 1 day | Gives token holders time to delegate before the vote snapshot is taken. Prevents last-minute delegation attacks. |
| `votingPeriod` | 36,000 blocks | ≈ 5 days | Wide enough for async global participation, tight enough for urgency. Covers at least 2 business cycles. |
| `proposalThreshold` | 5 PART (5e18) | — | Requires ≥ 5 weekly check-ins OR ≥ 1 meaningful funding contribution. Bars one-time drive-by proposers. Reachable by any consistent participant within a month. |
| `quorumNumerator` | 4% | — | Low initial quorum to bootstrap governance when token supply is small. Can be raised via governance (`updateQuorumNumerator()`). At scale, 4% of active participants is a strong signal. |

---

## TimelockController Parameters

| Parameter | Value | Justification |
|-----------|-------|---------------|
| `minDelay` | 2 days | Grace period for token holders to observe queued proposals and rage-quit or react before execution. |
| Proposers | `[governor]` only | Prevents bypassing the voting process. Only passed proposals can enter the queue. |
| Executors | `address(0)` (open) | Anyone can trigger execution after the delay — no centralised keeper required. |
| Admin | Revoked post-deploy | Once wired, the timelock is self-administered. Only governance can change roles. |

---

## Security Rationale

### Non-Transferable Token
Making `PART` non-transferable prevents:
- Token markets that recreate wealth-based voting
- Vote buying (you cannot sell governance power)
- Vampire attacks (buying participation history)

Delegation is preserved so users can nominate representatives (needed for Snapshot + Governor).

### AccessControlDefaultAdminRules
Used on `EarnerModule` and `Treasury` to enforce a 2-step admin transfer with a time delay.
This prevents accidental permanent loss of admin keys.

### CEI + ReentrancyGuard
All ETH-moving paths follow Checks-Effects-Interactions and use `ReentrancyGuard`.
This protects against re-entrancy even if a malicious `grantee` contract tries to re-enter.

### Pausable
Both `EarnerModule` and `Treasury` are pausable. This provides an emergency brake for:
- Oracle attacks affecting earning rates
- Discovered vulnerabilities requiring a freeze
- Bridge or RPC outages that distort epoch timing
