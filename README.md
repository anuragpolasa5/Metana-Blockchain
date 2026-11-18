# Batch Call Delegation — EIP-7702 & ERC-4337

This project demonstrates batch execution of multiple actions in a single transaction using:
- **Part A**: EIP-7702 delegation (Pectra upgrade)
- **Part B**: ERC-4337 account abstraction

## Project Structure

```
├── src/
│   ├── BatchCallDelegation7702.sol   # Core batch execution contract (Part A)
│   ├── BatchCallDelegation4337.sol   # ERC-4337 extension (Part B)
│   ├── MockEntryPoint.sol            # Mock EntryPoint for testing (Part B)
│   ├── Counter.sol                   # Simple counter for testing
│   ├── SimpleToken.sol               # ERC20 token for testing
│   └── interfaces/
│       ├── IAccount.sol              # ERC-4337 account interfaces + UserOperation struct
│       └── IEntryPoint.sol           # ERC-4337 entry point interface
├── test/
│   ├── BatchCallDelegation7702.t.sol # Part A tests (BE-5)
│   └── BatchCallDelegation4337.t.sol # Part B tests (BA-3)
├── script/
│   └── Deploy.s.sol                  # Foundry deployment script (BE-2)
└── script-viem/
    ├── batchExecute.js               # Viem EIP-7702 batch execution script (BE-3)
    ├── package.json
    └── .env.example
```

## Part A — EIP-7702 Batch Execution

### Contracts

**BatchCallDelegation7702** (BE-1) enables an EOA to delegate its execution to this contract via EIP-7702, allowing batch execution of multiple calls in a single transaction.

Features:
- `struct Call { address to; uint256 value; bytes data; }`
- `execute(Call[] calldata calls)` — iterates through calls, executes each via low-level `call`, reverts if any fail
- Emits `CallExecuted` event per successful call
- Accepts and forwards ETH via `receive()`

### Deployment (BE-2)

Deploy to Sepolia (or any Pectra-enabled testnet):

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

#### Deployed Contracts (Sepolia, chain ID 11155111)

All three contracts are deployed and verified on Sepolia Etherscan:

| Contract | Address | Etherscan |
| --- | --- | --- |
| BatchCallDelegation7702 | `0x7f9aB18a431519dba0BC29BE05c55F068F005CFA` | [View](https://sepolia.etherscan.io/address/0x7f9aB18a431519dba0BC29BE05c55F068F005CFA) |
| Counter | `0xBa9228B3A066504b32c868cd384c103D59f2748B` | [View](https://sepolia.etherscan.io/address/0xBa9228B3A066504b32c868cd384c103D59f2748B) |
| SimpleToken | `0x863EE610F5F6294B697a1500834C180dd386A93E` | [View](https://sepolia.etherscan.io/address/0x863EE610F5F6294B697a1500834C180dd386A93E) |

Deployment transactions:
- BatchCallDelegation7702: [0xb492522e…96ccdb8](https://sepolia.etherscan.io/tx/0xb492522e7f66cc0bcc6b80c2ddb49e4e2af4dae749f4ade78bb48ee0a96ccdb8)
- Counter: [0xa8b4a1a5…d84b99](https://sepolia.etherscan.io/tx/0xa8b4a1a5755b4cf0645a3634e2434d69e1758e005a916b4c50cdcfd1d3d84b99)
- SimpleToken: [0x1d9bab80…dd969a](https://sepolia.etherscan.io/tx/0x1d9bab80e6075c6a41287de37516cc741c056cacc54d563bd305e3d9e0dd969a)

### Viem Script — Batch Execution (BE-3)

The viem script (`script-viem/batchExecute.js`) batches three actions in one EIP-7702 transaction:

1. **Send 0.01 ETH** from the smart EOA to another account
2. **Transfer 100 ERC20 tokens** to another address
3. **Call `increment()` twice** on the Counter contract

#### Prerequisites

1. Deploy contracts (BatchCallDelegation7702, Counter, SimpleToken)
2. Fund the EOA with ETH and tokens
3. Configure `.env` (copy from `.env.example`)

#### Run

```bash
cd script-viem
npm install
cp .env.example .env
# Edit .env with your values
npm run execute
```

### Etherscan Transaction URL (BE-4)

> **Successful EIP-7702 batch execution on Sepolia:**
> https://sepolia.etherscan.io/tx/0xd1e45afe30af0a2a1e0abd649e84cce09288fa074a1ad074bdc54ec2c6d90ee3
>
> EOA `0xA5D3235b2C2e469c858CcD177Fe51d6186b9DA85` delegates to `0x7f9aB18a431519dba0BC29BE05c55F068F005CFA` and executes:
> - Action 1: Send 0.01 ETH to `0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e`
> - Action 2: Transfer 100 STK tokens to `0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e`
> - Action 3: Call `increment()` on Counter twice (counter went from 0 → 2)

### Deployed Contracts (Sepolia, chain ID 11155111)

All three contracts are deployed and source-verified on Sepolia Etherscan:

| Contract | Address | Etherscan |
| --- | --- | --- |
| BatchCallDelegation7702 | `0x7f9aB18a431519dba0BC29BE05c55F068F005CFA` | [View](https://sepolia.etherscan.io/address/0x7f9aB18a431519dba0BC29BE05c55F068F005CFA) |
| Counter | `0xBa9228B3A066504b32c868cd384c103D59f2748B` | [View](https://sepolia.etherscan.io/address/0xBa9228B3A066504b32c868cd384c103D59f2748B) |
| SimpleToken | `0x863EE610F5F6294B697a1500834C180dd386A93E` | [View](https://sepolia.etherscan.io/address/0x863EE610F5F6294B697a1500834C180dd386A93E) |

Deployment transactions:
- BatchCallDelegation7702: [0xb492522e…96ccdb8](https://sepolia.etherscan.io/tx/0xb492522e7f66cc0bcc6b80c2ddb49e4e2af4dae749f4ade78bb48ee0a96ccdb8)
- Counter: [0xa8b4a1a5…d84b99](https://sepolia.etherscan.io/tx/0xa8b4a1a5755b4cf0645a3634e2434d69e1758e005a916b4c50cdcfd1d3d84b99)
- SimpleToken: [0x1d9bab80…dd969a](https://sepolia.etherscan.io/tx/0x1d9bab80e6075c6a41287de37516cc741c056cacc54d563bd305e3d9e0dd969a)

## Part B — ERC-4337 Batch Execution

### Contracts

**BatchCallDelegation4337** (BA-1) extends `BatchCallDelegation7702` with ERC-4337 support:
- Inherits `BatchCallDelegation7702`, `IAccount`, `IAccountExecute`
- `validateUserOp()` — validates user operations (checks sender matches account address)
- `executeUserOp()` — decodes `Call[]` from `userOp.callData` and forwards to internal execute

**MockEntryPoint** (BA-2) implements `IEntryPoint`:
- `handleOps(UserOperation[] calldata ops, address payable beneficiary)` — for each operation:
  1. Calls `validateUserOp()` on the account
  2. If validation passes (returns 0), calls `executeUserOp()`
  3. Reverts with `ValidationFailed` if validation fails

### Viem Script — 4337 Batch Execution

The 4337 viem script (`script-viem/batchExecute4337.js`) batches the same three actions via a UserOperation submitted to the MockEntryPoint:

```bash
cd script-viem
npm install
npm run execute:4337
```

### On-Chain Evidence for 4337

> **Successful 4337 batch execution on Sepolia via MockEntryPoint.handleOps:**
> https://sepolia.etherscan.io/tx/0xf775399e8b9981e272551e44b287e7c21105e0f3fafa93091798bcd3fc99e75f
>
> - MockEntryPoint: [`0xF7535D4eAe45a7AeEa3818994F9c50EA43AF4EfD`](https://sepolia.etherscan.io/address/0xF7535D4eAe45a7AeEa3818994F9c50EA43AF4EfD)
> - BatchCallDelegation4337: [`0x0CBEFb12F8FB69BD049A50df3bcc9FE751771649`](https://sepolia.etherscan.io/address/0x0CBEFb12F8FB69BD049A50df3bcc9FE751771649)
> - Actions: ETH send + 100 token transfer + 2x counter increment (all via UserOp)

## Testing

Run all tests:

```bash
forge test -vvv
```

Run specific test files:

```bash
# Part A tests (BE-5)
forge test --match-contract BatchCallDelegation7702Test -vvv

# Part B tests (BA-3)
forge test --match-contract BatchCallDelegation4337Test -vvv
```

### Test Coverage

**Part A — BE-5 (7702):**
- `test_SendETH` — Send 0.01 ETH via batch execution
- `test_TransferERC20Tokens` — Transfer 100 ERC20 tokens via batch execution
- `test_IncrementCounterTwice` — Increment counter twice via batch execution
- `test_BatchAllThreeActions` — All three actions in a single batch
- `test_RevertOnFailedCall` — Revert with specific `CallFailed` error selector
- `test_RevertIfValueExceedsBalance` — Revert if value > contract balance
- `test_EmitsEventsPerCall` — Event emission per call
- `test_AcceptETH` — Accept ETH via receive()
- `test_ReentrancyViaMaliciousTarget` — Reentrancy via malicious target callback
- `test_SendETHToAddressZeroBurnsETH` — to == address(0) burns ETH
- `test_SelfCallToContractItself` — to == address(this) self-reentry
- `test_LargeCallsArray` — DoS test with large calls.length (100 calls)
- `test_EmptyCallsArray` — Edge case: empty array
- `test_AnyoneCanCallExecuteAndDrainFunds` — No access control on execute() (documents risk)
- `test_EIP7702DelegationSimulation` — EIP-7702 delegation simulation via vm.etch

**Part B — BA-3 (4337):**
- `test_SendETHVia4337` — Send ETH via MockEntryPoint → account
- `test_TransferERC20Via4337` — Transfer ERC20 tokens via MockEntryPoint → account
- `test_IncrementCounterTwiceVia4337` — Increment counter twice via MockEntryPoint → account
- `test_BatchAllThreeActionsVia4337` — All three actions in a single UserOp batch
- `test_ValidationFailsForWrongSender` — Validation fails for wrong sender
- `test_OnlyEntryPointCanCallValidateUserOp` — Only EntryPoint can call validateUserOp
- `test_OnlyEntryPointCanCallExecuteUserOp` — Only EntryPoint can call executeUserOp
- `test_ExecuteUserOpDecodesAndExecutesCalls` — executeUserOp decodes and executes calls
- `test_ExecuteUserOpRevertsOnFailedCall` — executeUserOp reverts on failed inner call
- `test_ValidateUserOpSecurityProperty` — Proves 4337 account-abstraction security property
- `test_UnauthorizedUserOpRejectedByHandleOps` — Unauthorized ops rejected via validation
- `test_MissingAccountFundsPrefund` — missingAccountFunds triggers ETH prefund to EntryPoint
- `test_HandleOpsFullFlow` — Full handleOps flow validation
- `test_HandleOpsRevertsOnValidationFailure` — handleOps reverts when targeting invalid account

---

## What I Learned

### EIP-7702 — Deep Understanding

EIP-7702 (introduced in the Pectra upgrade) fundamentally changes what an EOA can do without abandoning its private key. Here's how it works at the protocol level:

**Mechanism:**
- A new transaction type (type `0x04`) is introduced that includes an `authorization_list` — an array of `(chain_id, address, nonce, y_parity, r, s)` tuples.
- When the EVM processes this transaction, it iterates through the authorization list. For each entry, it recovers the signer from the signature, then sets that signer's account code to `0xef0100 || address` (a 23-byte delegation designator).
- Any subsequent call to the EOA resolves its code by reading the delegation target and executing that contract's bytecode in the context of the EOA (i.e., `address(this)` = the EOA, `msg.sender` = whoever called).

**Persistence & Revocation:**
- The delegation is **persistent** — it survives across transactions. Once set, the EOA's code remains `0xef0100 || target` until explicitly changed.
- Revocation is done by signing a new authorization pointing to `address(0)`, which clears the code and restores the EOA to its normal state.
- Each authorization includes a nonce to prevent replay attacks. The nonce must match the EOA's current nonce at the time the authorization is applied.

**Security Model:**
- The canonical security pattern is `require(msg.sender == address(this))` inside `execute()`. This ensures only the EOA itself (sending a tx to itself) can invoke batch operations — a third party cannot call `execute()` on someone else's delegated EOA.
- Without this guard, anyone can call functions on a delegated EOA since the code is publicly accessible. Our tests (`test_AnyoneCanCallExecuteAndDrainFunds`) explicitly document this vulnerability.
- The authorization signature binds to a specific chain ID, preventing cross-chain replay of delegations.

**How it differs from ERC-4337 smart accounts:**
- With 7702, the EOA retains its private key and nonce management. It's still an EOA on-chain — it just temporarily (or persistently) has code.
- No need for a factory, no CREATE2 counterfactual addresses, no initCode. The account already exists.
- The EOA can still send normal transactions (non-batched). Delegation is additive, not replacing.

### ERC-4337 — Deep Understanding

ERC-4337 defines a system for account abstraction without requiring protocol changes. It introduces a separate mempool for `UserOperations` and a singleton `EntryPoint` contract that orchestrates validation and execution.

**Architecture:**
```
User → Bundler → EntryPoint.handleOps([UserOp]) → Account.validateUserOp() → Account.executeUserOp()
```

- **UserOperation**: A struct containing `sender`, `nonce`, `callData`, gas parameters, `signature`, and optional `paymasterAndData`. It's the ERC-4337 equivalent of a transaction.
- **EntryPoint**: A trusted singleton contract (deployed at a canonical address). It receives batches of UserOps from bundlers, validates each one, then executes them.
- **Account Contract**: Implements `IAccount` (for validation) and optionally `IAccountExecute` (for execution). The account decides its own validation logic — ECDSA, multisig, social recovery, passkeys, etc.

**Two-Phase Execution:**
1. **Validation Phase** (`validateUserOp`): The EntryPoint calls the account to verify the UserOp is authorized. This phase has restrictions — no access to other accounts' storage, limited opcodes — to allow bundlers to simulate safely. Returns 0 for success, 1 for failure.
2. **Execution Phase** (`executeUserOp`): Only called if validation passes. The account decodes `callData` and performs the requested actions. No restrictions here — full EVM access.

**Gas Accounting & Prefunding:**
- The account must deposit ETH into the EntryPoint (or use a paymaster) to pay for gas. The `missingAccountFunds` parameter in `validateUserOp` tells the account how much it needs to deposit.
- Our test (`test_MissingAccountFundsPrefund`) verifies this flow: the account sends ETH to the EntryPoint during validation.

**Security Properties:**
- Only the EntryPoint can call `validateUserOp` and `executeUserOp` (enforced by `onlyEntryPoint` modifier). This prevents anyone from bypassing validation.
- The validation checks `userOp.sender == address(this)` to ensure the UserOp was intended for this specific account — preventing one account from being tricked into executing another account's operations.
- Signature verification (omitted in our mock for simplicity) is where the real authorization happens in production.

**How 7702 and 4337 complement each other:**
- EIP-7702 can delegate an EOA's code to an ERC-4337 account implementation, giving the EOA full account-abstraction capabilities while retaining its original address and key.
- Our `BatchCallDelegation4337` demonstrates exactly this: it inherits the 7702 batch execution logic AND implements the 4337 interfaces, making it usable both ways.

### Other Key Learnings

- **Batch Call Patterns**: The `Call` struct pattern (target + value + data) is a universal building block in smart account designs. Low-level `call` enables arbitrary contract interaction without compile-time ABI knowledge — this is what makes batch execution powerful.

- **Viem's EIP-7702 Support**: The `signAuthorization` and `authorizationList` APIs in viem abstract the complexity of type-4 transactions. Gas estimation for 7702 transactions requires care — the authorization is applied before execution, so static `eth_call` without the auth context will fail.

## Problems & Solutions

**Problem: No shared git history for PR creation**
When pushing to the assignment repository, my branch had no common ancestor with `main` because I initialized the Foundry project locally from scratch. GitHub refused to create a PR between branches with unrelated histories. I solved this by doing a `git reset --soft origin/main` which re-parented my commit on top of the remote main branch while preserving all my staged changes.

**Problem: MockEntryPoint routing and validation logic**
Initially, I designed `validateUserOp` to check `userOp.sender == owner`, but the MockEntryPoint uses `op.sender` as the address to call (the account contract). This meant the sender field needed to be the account's own address for routing to work, creating a circular dependency in my validation logic. I resolved this by changing the validation to check `userOp.sender == address(this)` — which confirms the UserOp is intended for this specific account instance.

**Problem: Memory vs Calldata array handling in executeUserOp**
The `execute()` function accepts `calldata` arrays, but `abi.decode` returns `memory` arrays. I couldn't directly pass a memory array to a function expecting calldata. I solved this by creating `_executeInternal(Call[] memory calls)` which mirrors the execute logic but accepts memory parameters, keeping the public `execute()` function efficient for direct calldata usage.

## Testing Approach

I structured my tests around the three required actions (ETH transfer, ERC20 transfer, Counter increment), testing each both individually and as a combined batch:

**Individual action tests**: Each action is tested in isolation to verify correctness independent of the batch mechanism. This makes it easy to identify which action fails if a batch test breaks.

**Combined batch test**: `test_BatchAllThreeActions` and `test_BatchAllThreeActionsVia4337` verify that all actions execute correctly in a single transaction, confirming the batch mechanism works end-to-end.

**Failure and edge cases**:
- `test_RevertOnFailedCall` — confirms atomicity (if one call fails, everything reverts)
- `test_EmitsEventsPerCall` — verifies event emission for each call (important for off-chain tracking)
- `test_AcceptETH` — ensures the receive() function works for ETH forwarding
- `test_ValidationFailsForWrongSender` — confirms unauthorized operations are rejected
- `test_OnlyEntryPointCanCall` — verifies access control (only EntryPoint can trigger account functions)

**What I deliberately omitted**: I did not test gas estimation, paymaster flows, or signature verification because the MockEntryPoint is intentionally simplified. In production, `validateUserOp` would verify ECDSA signatures against the userOpHash, but for this assignment the focus is on the batch execution flow rather than cryptographic validation.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for viem script)
- A Pectra-enabled testnet RPC (Sepolia, Hoodi, or Holesky)

## License

MIT
