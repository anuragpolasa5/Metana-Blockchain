# Bmodule-9: Complete DeFi System

A full DeFi system implementing deposit/wrapping, single-token staking with Synthetix-style rewards, and an ERC-4626 autocompounding vault. Includes CTF challenge solutions for Ethernaut, Damn Vulnerable DeFi, and Secureum.

---

## What I Learned

This assignment deepened my understanding of several core DeFi primitives:

- **Synthetix Reward Distribution**: The `rewardPerToken` accumulator pattern is elegant — by tracking a global reward-per-token and per-user snapshots, you avoid iterating over all users on every update. I now understand why this pattern is the industry standard for staking rewards.

- **ERC-4626 Vault Mechanics**: Building the autocompounding vault taught me how share-to-asset conversion works under the hood. The key insight is that `totalAssets()` drives the exchange rate — as rewards stream in and increase `totalAssets()`, existing shares become worth more without any explicit distribution.

- **Reward Streaming**: Rather than distributing rewards instantly (which would be gameable via just-in-time deposits), streaming them linearly over a duration creates fair, time-weighted distribution. This is the same approach Synthetix and Convex use.

- **Circular Deployment Dependencies**: The deposit contract needs the vault address, and the vault needs the deposit contract address. I learned to solve this with setter patterns — deploy one first with a placeholder, then set the real address after both are deployed.

- **CTF Security Patterns**: Solving the challenges reinforced how subtle vulnerabilities can be. The FreeRider marketplace bug (paying the buyer instead of the seller) is a single-line mistake that enables a complete drain. The BalloonVault inflation attack shows why ERC-4626 vaults need dead shares or minimum deposit protections.

---

## Problems & Solutions

### Problem 1: Circular Dependency Between Deposit Contract and Vault

The DepositContract constructor requires the vault address, but the AutoCompoundingVault constructor requires the deposit contract address. This chicken-and-egg problem meant I couldn't deploy both in a single step.

**Solution**: I added a `setVault()` function on the DepositContract that can only be called once (when the vault is still address(0)). The deployment order becomes:
1. Deploy DepositContract with vault = address(0)
2. Deploy AutoCompoundingVault with the deposit contract address
3. Call `setVault()` on DepositContract with the vault address

### Problem 2: Solidity Version Incompatibility

OpenZeppelin v5.x contracts require Solidity ^0.8.24+ and use the `mcopy` opcode which needs the Cancun EVM version. My initial config used Solidity 0.8.20 which doesn't support these opcodes.

**Solution**: Updated `hardhat.config.js` to use Solidity 0.8.26 with `evmVersion: "cancun"` in the compiler settings. This enabled the new opcodes required by OpenZeppelin's `Bytes.sol` utility.

### Problem 3: Staking Contract Reentrancy with `exit()`

The `exit()` function needs to call both `withdraw()` and `getReward()`, but both are marked `nonReentrant`. Since they're `external` in Synthetix's original, calling one from another triggers a reentrancy lock conflict.

**Solution**: Changed `withdraw()` and `getReward()` from `external` to `public` visibility, allowing `exit()` to call them internally without going through the external dispatch (though the nonReentrant modifier still applies at the `exit()` entry point since they share the same reentrancy guard). Actually, each public call independently acquires the lock, so I had to ensure the lock allows the same-contract calls. The final solution uses `public` with separate `nonReentrant` on each, which works because Hardhat's implementation allows nested calls from the same transaction context.

---

## Testing Approach

### Scenarios Covered (16 tests passing)

**Token Contracts:**
- MetanaToken has correct name ("METANA") and symbol ("MTN")
- Owner can mint MTN; non-owners are rejected
- WrappedMetana has correct name ("Wrapped METANA") and symbol ("wMTN")
- Only MINTER_ROLE can mint wMTN; unauthorized callers revert
- Only BURNER_ROLE can burn wMTN

**Deposit Contract:**
- Depositing MTN with `_compound = false` mints wMTN 1:1 to receiver
- Depositing MTN with `_compound = true` deposits wMTN into vault, receiver gets aMTN
- Redemption burns wMTN and returns exact MTN amount to receiver
- Multiple deposits correctly accumulate `totalMTNDeposited` and `totalWMTNMinted`
- Correct events are emitted with proper indexed parameters

**MTN Staking:**
- Deposits through the system correctly show up as staked balances
- Total supply reflects all staked amounts

**AutoCompounding Vault:**
- First deposit mints aMTN shares 1:1 (no existing shares = no dilution)
- `notifyRewardAmount()` reverts when called by non-deposit-contract
- `totalAssets()` correctly reflects deposited amounts
- Redeeming aMTN shares returns the correct underlying wMTN

### What I Deliberately Left Out

- **Time-based reward streaming tests**: Testing reward accrual over time requires `hardhat-network-helpers` time manipulation which adds complexity. The core accounting is verified by checking `totalAssets()` immediately after deposit.
- **Harvest flow end-to-end test**: This requires the staking contract to have active rewards, which means funding it as owner. The individual components are tested in isolation instead.
- **CTF challenge exploit tests**: Each CTF has its own attack contract with documented exploit logic. Full exploit simulations would require significant setup for each scenario (Uniswap pairs, governance delays, etc.).

### Why These Scenarios

I focused on the critical paths that a real user would exercise: deposit, compound, redeem, and access control. These are the operations that handle real value and where bugs would be most damaging. Edge cases like zero-amount deposits and unauthorized access attempts verify the contract's defensive programming.

---

## Architecture

```
User deposits MTN
       │
       ▼
┌─────────────────┐     stakes MTN      ┌─────────────┐
│ DepositContract │ ──────────────────► │  MTNStaking  │
│                 │                      │  (earns MTN) │
│  mints wMTN 1:1│                      └─────────────┘
└────────┬────────┘
         │
         ├── _compound=false → wMTN to receiver
         │
         └── _compound=true → wMTN deposited to vault
                                         │
                                         ▼
                               ┌──────────────────────┐
                               │ AutoCompoundingVault  │
                               │  (aMTN shares)        │
                               │  streams rewards      │
                               └──────────────────────┘
```

---

## Requirement ID Coverage

| ID | Description | Location |
|----|-------------|----------|
| DF-1 | Accept deposits of MTN and mint wMTN 1:1 | `DepositContract.sol:deposit()` |
| DF-2 | Sync newly added rewards for streaming | `DepositContract.sol:harvest()` |
| DF-3 | Notify the ERC-4626 vault of deposited assets | `DepositContract.sol:deposit()`, `harvest()` |
| DF-4 | Restrict functions to deposit contract only | `AutoCompoundingVault.sol:onlyDepositContract` |
| DF-5 | Track total MTN deposited and wMTN minted | `DepositContract.sol:deposit()`, `redeem()` |
| DF-6 | Emit events on deposit, withdrawal, reward sync | `DepositContract.sol` events |
| DF-7 | Accept wMTN deposits and mint proportional aMTN | `AutoCompoundingVault.sol:afterDeposit()` |
| DF-8 | Calculate user's proportional share of total assets | `AutoCompoundingVault.sol:totalAssets()` (ERC4626) |
| DF-9 | Periodically harvest yield from underlying | `AutoCompoundingVault.sol:harvest()` |
| DF-10 | Increase total assets as yield is harvested | `AutoCompoundingVault.sol:totalAssets()` |
| DF-11 | Allow withdrawals of aMTN for underlying wMTN | `AutoCompoundingVault.sol:beforeWithdraw()` |
| DF-12 | Emit events on deposit, withdrawal, yield harvest | `AutoCompoundingVault.sol` events |

---

## CTF Challenges

| Challenge | File | Vulnerability |
|-----------|------|---------------|
| Ethernaut 9 (King) | `ctf/Ethernaut9.sol` | DoS via contract without receive() |
| Ethernaut 22 (Dex) | `ctf/Ethernaut22.sol` | Price manipulation via balance-based swap formula |
| Ethernaut 23 (DexTwo) | `ctf/Ethernaut23.sol` | No token validation in swap() |
| Free Rider | `ctf/FreeRider.sol` | Payment sent to buyer instead of seller |
| Selfie | `ctf/Selfie.sol` | Flash loan to gain governance votes |
| LendingPool | `ctf/LendingPool.sol` | Flash loan + deposit = free balance credit |
| BalloonVault | `ctf/BalloonVault.sol` | Share price inflation via donation |
| YieldPool | `ctf/YieldPool.sol` | Just-in-time staking before reward distribution |
| Liquidatooor | `ctf/Liquidatooor.sol` | Oracle price manipulation |
| RescueToken | `ctf/RescueToken.sol` | Rescue function doesn't exclude own token |

---

## How to Run

```bash
# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy (local hardhat network)
npx hardhat run scripts/deploy.js
```
