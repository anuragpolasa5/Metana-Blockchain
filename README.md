# Role-Based Rewards Pool

Two-contract system: **CommunityToken** (ERC-20) + **RewardsVault**, secured entirely with OpenZeppelin AccessControl.

## Quick start

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Project layout

```
contracts/
  CommunityToken.sol   — ERC-20 + ERC20Pausable + AccessControl
  RewardsVault.sol     — Donation vault + AccessControl + Pausable + ReentrancyGuard
test/
  RewardsPool.test.js  — 30+ unit tests (Hardhat + Chai)
hardhat.config.js
package.json
```

## Roles

| Role constant | Contract(s) | Privileges |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | CommunityToken | Grant / revoke all roles |
| `DEFAULT_ADMIN_ROLE` | RewardsVault | Grant / revoke all roles + set foundation wallet |
| `MINTER_ROLE` | CommunityToken | Mint new reward tokens |
| `PAUSER_ROLE` | Both | Pause / unpause |
| `TREASURER_ROLE` | RewardsVault | Withdraw pooled ETH |
| `AUDITOR_ROLE` | RewardsVault | Alias for `PAUSER_ROLE` |

## Key flow

1. Anyone calls `RewardsVault.donate{value: X}()` → receives `X / 0.01 ETH` CommunityTokens
2. Treasurer calls `withdraw(amount)` → ETH goes to `foundationWallet`
3. Auditor / Pauser can freeze both contracts in an emergency
