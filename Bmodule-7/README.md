# BModule-7: Participation-Based DAO + Crystal DAO CTF (Challenge 7)

## What I Learned

This assignment deepened my understanding of several key blockchain governance concepts:

- **Participation-based governance vs plutocratic DAOs**: Traditional token DAOs let wealthy users buy voting power. By making PART non-transferable and earned through on-chain actions, the system ensures governance power reflects genuine participation, not capital.

- **OpenZeppelin Governor stack**: I learned how `Governor`, `GovernorSettings`, `GovernorVotes`, `GovernorVotesQuorumFraction`, and `GovernorTimelockControl` work together. The diamond inheritance pattern requires careful override resolution, and each extension adds a specific governance feature.

- **ERC20Votes and IERC5805 (EIP-6372)**: Implementing vote checkpointing with `clock()` returning `block.number` ensures that voting power snapshots are taken at the right moment. This is critical for preventing flash-loan governance attacks — votes are counted based on holdings at the proposal's snapshot block, not the current block.

- **TimelockController as a security layer**: The 2-day delay between vote success and execution gives the community time to react to potentially malicious proposals. Wiring the Governor as sole proposer and revoking the deployer's admin role achieves full decentralisation.

- **ERC-1167 Minimal Proxy (Clone) vulnerabilities**: Challenge 7 taught me that constructors run in the implementation's storage context, NOT the clone's. If a factory forgets to call `initialize()`, the clone's storage is zeroed and open to takeover. This mirrors real-world exploits like the Wormhole uninitialized proxy bug.

- **CEI (Checks-Effects-Interactions) pattern**: Combined with `ReentrancyGuard`, this provides defence-in-depth against re-entrancy. All state mutations happen before any external calls.

## Problems & Solutions

### Problem 1: Diamond Inheritance Override Conflicts

The `ParticipationGovernor` inherits from 6 contracts (Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl). Solidity requires explicit override resolution when multiple base contracts define the same function.

**Solution**: I identified every function that exists in multiple bases (`votingDelay`, `votingPeriod`, `proposalThreshold`, `quorum`, `state`, `proposalNeedsQueuing`, `_queueOperations`, `_executeOperations`, `_cancel`, `_executor`) and added `override(Contract1, Contract2)` with `super` delegation to the correct extension.

### Problem 2: Non-transferable Token Breaking ERC20Votes

Initially I was concerned that blocking `_update()` would break the voting checkpoint system. ERC20Votes hooks into `_update()` to update vote checkpoints.

**Solution**: By overriding `_update()` with `override(ERC20, ERC20Votes)` and calling `super._update()` for allowed operations (mint/burn), the checkpointing system works correctly for mints while still blocking transfers. Delegation (which doesn't call `_update`) is completely unaffected.

### Problem 3: Auto-delegation Race Condition

If a user receives tokens but never calls `delegate()`, their voting power is zero (ERC20Votes requires explicit delegation). This would be a terrible UX — users would earn tokens but have no voting power.

**Solution**: The `mint()` function checks `if (delegates(to) == address(0))` and auto-delegates to self. This ensures that the first mint immediately activates voting power. Subsequent mints don't re-delegate (preserving any existing delegation choice).

### Problem 4: Funding Rate Precision

The funding rate calculation (`msg.value * FUNDING_RATE`) needed careful handling to avoid overflow or precision loss.

**Solution**: Since `msg.value` is in wei (18 decimals) and `FUNDING_RATE = 100`, the product `msg.value * 100` directly gives token amounts in 18-decimal precision. No additional scaling needed — 0.01 ETH (1e16 wei) × 100 = 1e18 = 1 PART token.

## Testing Approach

### Test Suite Structure

The test suite (`test/ParticipationDAO.t.sol`) contains 24 tests covering the full governance lifecycle, organised by requirement ID:

| Category | Tests | What's Covered |
|----------|-------|----------------|
| DAO-1: Earning | 8 tests | checkIn grants 1 token, auto-delegates, rejects double-claims, allows next epoch; fund earns proportional tokens, enforces user/global caps, reverts on zero |
| DAO-2: Threshold | 1 test | Proposal rejected when caller has insufficient PART |
| DAO-3: Treasury Security | 2 tests | Direct releaseETH/setParam reverts without TIMELOCK_ROLE |
| DAO-4: Cap Views | 2 tests | remainingUserCap and remainingGlobalCap decrease correctly |
| DAO-5: Delegation | 2 tests | Delegate to another, claimedCheckIn view |
| DAO-6: Full Lifecycle | 2 tests | Complete propose→vote→queue→execute cycle; proposal defeated without quorum |
| DAO-7: setParam | 1 test | Governance proposal updates a treasury parameter end-to-end |
| DAO-8: Pause | 3 tests | Pause blocks checkIn/fund; unpause restores functionality |

### Edge Cases Tested

- **Double check-in same epoch**: Reverts with `AlreadyClaimedCheckIn`
- **Zero-value fund()**: Reverts with `ZeroContribution`
- **Global cap saturation**: 10 users each hit their cap → 11th user reverts
- **Quorum failure**: Proposal with no votes is defeated
- **Unauthorised proposal**: Zero-balance user cannot propose
- **Unauthorised treasury access**: Direct calls to treasury without timelock revert

### Challenge 7 Tests (5 tests)

- Clone admin is address(0) (confirms vulnerability exists)
- initialize() is callable by anyone on uninitialised clone
- Full rescue: initialize → withdraw → 100 ETH recovered
- Original DAO admin cannot withdraw (admin slot is zero)
- Double-initialize prevention (re-init after rescue reverts)

### What I Deliberately Left Out

- **Fuzz testing on governance**: The Governor's internal state machine is well-tested by OpenZeppelin. I focused integration tests on the wiring rather than re-testing OZ internals.
- **Gas optimisation tests**: While gas reports are generated, I didn't add assertions on gas limits since this is a testnet deployment.
- **Multi-epoch stress testing**: Testing 100+ epochs would add execution time without meaningful coverage gain — the epoch boundary logic is the same regardless of epoch number.

## Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| ParticipationToken | `0xBD12c1aC45be64335b778849260446A47a05E270` |
| DAOTimelock | `0xdacd62dA25C8Af696c527aE04e152D9141841B03` |
| Treasury | `0x0B09Fc59FE19F5eEA38DCe7E521Dbe1d527005Ef` |
| EarnerModule | `0x6D0E8624c6f74c42947f73984ca3FA116024cA60` |
| ParticipationGovernor | `0xBA6C19Df9CB7A903D569BdD0467E29ABbbe452C4` |

All contracts are verified on [Sepolia Etherscan](https://sepolia.etherscan.io).

## How to Run

```bash
# Install dependencies
forge install

# Build
forge build

# Run all tests (31/31 pass)
forge test -vvv

# Deploy to Sepolia
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```
