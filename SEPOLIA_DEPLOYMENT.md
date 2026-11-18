# Sepolia Deployment — Bmodule-9 DeFi System

**Network:** Sepolia testnet (chainId `11155111`)
**Deployer:** `0xA5D3235b2C2e469c858CcD177Fe51d6186b9DA85`
**Date:** 2026-06-24
**Commit:** post-PR-#13-review (custom errors, reentrancy guard, zero checks, stray-MTN fix, accounting hooks)

## Contract Addresses

| Contract | Address | Etherscan |
|----------|---------|-----------|
| MetanaToken (MTN) | `0x78E135411A3Bc9185728bAC4eA5aE89E99e6A21F` | [view](https://sepolia.etherscan.io/address/0x78E135411A3Bc9185728bAC4eA5aE89E99e6A21F) |
| WrappedMetana (wMTN) | `0xdAc5F458cCFb06f800D0EC7Cc4c9171b0f2CD26B` | [view](https://sepolia.etherscan.io/address/0xdAc5F458cCFb06f800D0EC7Cc4c9171b0f2CD26B) |
| MTNStaking | `0xAaf8138606473733089E534bDa9206b026f1e5B9` | [view](https://sepolia.etherscan.io/address/0xAaf8138606473733089E534bDa9206b026f1e5B9) |
| DepositContract | `0xfeDda16763FE733Ee2567E345De6F2c72D5ee11F` | [view](https://sepolia.etherscan.io/address/0xfeDda16763FE733Ee2567E345De6F2c72D5ee11F) |
| AutoCompoundingVault (aMTN) | `0x90455e67308bD5Ab2c295b96eEbB187DC953ab58` | [view](https://sepolia.etherscan.io/address/0x90455e67308bD5Ab2c295b96eEbB187DC953ab58) |

## On-chain Wiring (verified)

- `vault.symbol() == "aMTN"` ✅
- `vault.asset() == wMTN` ✅
- `vault.depositContract() == DepositContract` ✅
- `deposit.wMTN() == wMTN` ✅
- `deposit.autoCompoundingVault() == AutoCompoundingVault` ✅
- `deposit.stakingContract() == MTNStaking` ✅
- `DepositContract` holds wMTN `MINTER_ROLE` + `BURNER_ROLE`; owns `MTNStaking`.
- `deposit.owner() == deployer`.

## Notes

- Contracts are **not yet source-verified** on Etherscan (bytecode only). Verify with:
  `npx hardhat verify --network sepolia <address> <constructor args>` (config: `hardhat.config.js`).
- 1000 MTN minted to the deployer for demo flows.
