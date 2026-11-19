# Echidna Exercises - Smart Contract Security Testing (Module 14)

This repository contains completed Echidna exercises for smart contract security testing. These exercises were created by [Trail of Bits](https://www.trailofbits.com/) and are designed to teach property-based testing of Solidity smart contracts using [Echidna](https://github.com/crytic/echidna).

---

## What I Learned

This module deepened my understanding of **property-based fuzzing** as a smart contract testing methodology. Key takeaways:

1. **Property-based testing vs unit testing:** Instead of writing specific test cases, you define invariants (properties that must always hold), and the fuzzer generates thousands of random transaction sequences to try to break them. This catches edge cases that manual testing would miss.

2. **How Echidna works:** Echidna generates random function calls with random parameters, checking if any sequence of calls can violate defined properties. It uses coverage-guided fuzzing to explore new code paths efficiently.

3. **Common Solidity vulnerability patterns:**
   - **Integer underflow/overflow** (Exercise 1 & 4): Before Solidity 0.8, arithmetic operations could silently wrap. Even with 0.8+ protections, explicit `require()` checks provide clearer error messages and intent.
   - **Access control via constructor confusion** (Exercise 2): Using a named function instead of the `constructor` keyword allows anyone to call it and claim ownership.
   - **Flash loan exploitation patterns** (Exercises 5-8): Flash loans enable atomic attacks where massive capital is borrowed, used to exploit logic flaws, and returned — all in a single transaction.

4. **Assertion mode vs property mode:** Exercise 4 taught me that Echidna can detect `assert()` failures directly (assertion mode), which is useful for embedding invariant checks inside the contract logic itself rather than in separate test contracts.

5. **The importance of accounting consistency** (Exercise 6): When a contract maintains internal accounting (`poolBalance`) that can diverge from actual state (`balanceOf`), attackers can exploit the discrepancy.

6. **DeFi composability risks** (Exercises 5-8): Each DeFi exercise demonstrated how composability — the ability for contracts to interact — creates attack surfaces. A flash loan pool combined with a reward pool creates an exploitation vector that neither system would have in isolation.

---

## Problems & Solutions

### Problem 1: Rebasing onto an existing repository
The target GitHub repo already had a `main` branch with its own history. When I tried to push my new branch, the PR creation failed with "no history in common with main." I had to rebase my branch onto `origin/main` and resolve the README conflict before the PR could be created.

### Problem 2: Understanding the Side Entrance vulnerability (Exercise 7)
Initially, I struggled to see how `deposit()` during a flash loan callback constituted an exploit. The key insight was that the flash loan only checks `address(this).balance >= balanceBefore` — it doesn't care *how* the balance was restored. By calling `deposit()`, the borrowed ETH is returned to the pool (satisfying the check) but simultaneously credits the attacker's internal balance mapping, which can be withdrawn later.

### Problem 3: Echidna configuration for ETH-based tests (Exercises 5 & 7)
The DeFi exercises involving ETH required the `balanceContract` configuration option to supply the test contract with enough ETH during deployment. Without this, the constructor would fail when trying to fund the pool and receiver contracts. The `multi-abi` option was also essential — it allows Echidna to call functions on any contract in the deployment, not just the test contract.

### Problem 4: Assertion mode configuration (Exercise 4)
Initially I defined explicit property functions for Exercise 4, but the exercise specifically requires using `assert()` statements inside the transfer function. The key was setting `testMode: assertion` in the config file, which tells Echidna to look for `assert()` failures rather than boolean-returning property functions.

---

## Testing Approach

### Property Design Strategy
For each exercise, I designed properties based on the core invariant that should hold:

| Exercise | Property | Rationale |
|----------|----------|-----------|
| 1 | `balances[caller] <= 10000` | No one should gain tokens from nothing |
| 2 | `is_paused == true` | Permanently paused contract cannot be unpaused |
| 3 | `totalMinted <= totalMintable` | Minting cap must be enforced |
| 4 | `assert(balance_after <= balance_before)` | Transfer cannot create tokens |
| 5 | `receiver.balance >= initialBalance` | Third parties cannot drain a contract |
| 6 | `flashLoan(10)` succeeds | Pool should never become permanently DoSed |
| 7 | `pool.balance >= initialBalance` | Pool funds cannot be extracted |
| 8 | `attackerRewards < 99% of total` | No single actor should capture all rewards |

### What I Tested
- **Happy path:** Normal transfers, legitimate minting, proper flash loan usage
- **Edge cases:** Zero-value transfers, self-transfers, maximum values
- **Attack vectors:** Underflow exploitation, ownership takeover, unauthorized flash loan initiation, flash loan + deposit reentrancy, flash loan reward manipulation

### What I Deliberately Left Out
- **Gas optimization testing:** Not the focus of security-oriented exercises
- **Multi-user interaction sequences:** Echidna handles this automatically through random caller generation
- **Time-dependent attacks for Exercise 8:** The reward round timing (5-day window) would require Echidna's time manipulation features with custom configuration, which adds complexity beyond the exercise scope

### Slither Static Analysis
Static analysis was run on Exercises 1-4 using Slither. The full report is in [SLITHER_ANALYSIS.md](./SLITHER_ANALYSIS.md). Key findings include high-severity integer underflow issues (fixed), the ownership takeover vulnerability (fixed), and informational style warnings (documented).

---

## Requirement ID Reference

| ID | Exercise | Requirement |
|----|----------|-------------|
| EX1-01 | 1 | Use proper constructor to prevent ownership takeover |
| EX1-02 | 1 | Add balance check to prevent underflow in transfer |
| EX1-03 | 1 | Define Echidna property verifying balance <= 10000 |
| EX2-01 | 2 | Fix constructor pattern to prevent ownership reclaim |
| EX2-02 | 2 | Ensure resume() is inaccessible after ownership removal |
| EX2-03 | 2 | Define property verifying contract stays paused |
| EX3-01 | 3 | Implement mint with totalMintable enforcement |
| EX3-02 | 3 | Custom initialization and minting properties |
| EX4-01 | 4 | Add assert() post-conditions to transfer |
| EX4-02 | 4 | Fix underflow to satisfy assertions |
| EX4-03 | 4 | Configure assertion mode testing |
| EX5-01 | 5 | Identify unauthorized flash loan initiation vulnerability |
| EX5-02 | 5 | Document missing initiator verification in receiver |
| EX5-03 | 5 | Property: receiver balance cannot decrease |
| EX6-01 | 6 | Identify poolBalance vs actual balance divergence |
| EX6-02 | 6 | Property: flash loans always succeed |
| EX7-01 | 7 | Identify deposit-during-flashloan vulnerability |
| EX7-02 | 7 | Property: pool balance cannot decrease |
| EX8-01 | 8 | Set up flash loan pool for attack |
| EX8-02 | 8 | Identify proportional reward manipulation |
| EX8-03 | 8 | Property: attacker cannot claim >99% of rewards |

---

## How to Run

### Prerequisites
- [Echidna](https://github.com/crytic/echidna) (v2.0+)
- [Slither](https://github.com/crytic/slither) (v0.9+)
- Solidity Compiler (solc 0.8.0+)

### Running Echidna on Exercises 1-4
```bash
echidna exercises/exercise1/TestToken.sol --contract TestToken --config exercises/exercise1/config.yaml
echidna exercises/exercise2/TestToken.sol --contract TestToken --config exercises/exercise2/config.yaml
echidna exercises/exercise3/TestMintableToken.sol --contract TestMintableToken --config exercises/exercise3/config.yaml
echidna exercises/exercise4/TestToken.sol --contract TestToken --config exercises/exercise4/config.yaml
```

### Running Echidna on DeFi Exercises (5-8)
```bash
echidna exercises/exercise5/NaiveReceiverEchidna.sol --contract NaiveReceiverEchidna --config exercises/exercise5/config.yaml
echidna exercises/exercise6/UnstoppableEchidna.sol --contract UnstoppableEchidna --config exercises/exercise6/config.yaml
echidna exercises/exercise7/SideEntranceEchidna.sol --contract SideEntranceEchidna --config exercises/exercise7/config.yaml
echidna exercises/exercise8/TheRewarderEchidna.sol --contract TheRewarderEchidna --config exercises/exercise8/config.yaml
```

### Running Slither
```bash
slither exercises/exercise1/token.sol
slither exercises/exercise2/token.sol
slither exercises/exercise3/MintableToken.sol
slither exercises/exercise4/token.sol
```

---

## Credits

- Exercises created by [Trail of Bits](https://www.trailofbits.com/)
- [Echidna](https://github.com/crytic/echidna) - Smart contract fuzzer
- [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) - DeFi security challenges
- [Slither](https://github.com/crytic/slither) - Solidity static analysis framework
