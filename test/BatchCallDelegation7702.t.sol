// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BatchCallDelegation7702} from "../src/BatchCallDelegation7702.sol";
import {Counter} from "../src/Counter.sol";
import {SimpleToken} from "../src/SimpleToken.sol";

/// @dev Malicious contract that attempts reentrancy on BatchCallDelegation7702
contract ReentrantAttacker {
    BatchCallDelegation7702 public target;
    uint256 public attackCount;

    constructor(address _target) {
        target = BatchCallDelegation7702(payable(_target));
    }

    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
            calls[0] = BatchCallDelegation7702.Call({
                to: address(this),
                value: 0.01 ether,
                data: ""
            });
            target.execute(calls);
        }
    }
}

/**
 * @title BatchCallDelegation7702Test
 * @notice Foundry tests for Part A: EIP-7702 batch call delegation.
 * @dev BE-5: Write Foundry tests covering the three actions via BatchCallDelegation7702.
 */
contract BatchCallDelegation7702Test is Test {
    BatchCallDelegation7702 public batchCaller;
    Counter public counter;
    SimpleToken public token;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public deployer = makeAddr("deployer");

    event CallExecuted(uint256 indexed index, address indexed to, uint256 value, bytes data);

    function setUp() public {
        vm.startPrank(deployer);

        batchCaller = new BatchCallDelegation7702();
        counter = new Counter();
        token = new SimpleToken(1_000_000);

        vm.deal(address(batchCaller), 10 ether);
        token.transfer(address(batchCaller), 1000 * 10 ** 18);

        vm.stopPrank();
    }

    // ==================== Core Action Tests (BE-5) ====================

    // BE-5: Test Action 1 - Send 0.01 ETH from the smart EOA to another account
    function test_SendETH() public {
        uint256 bobBalanceBefore = bob.balance;

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(bob.balance, bobBalanceBefore + 0.01 ether, "Bob should receive 0.01 ETH");
    }

    // BE-5: Test Action 2 - Transfer 100 ERC20 tokens to another address
    function test_TransferERC20Tokens() public {
        uint256 bobTokensBefore = token.balanceOf(bob);

        bytes memory transferData = abi.encodeWithSelector(token.transfer.selector, bob, 100 * 10 ** 18);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(token), value: 0, data: transferData});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(token.balanceOf(bob), bobTokensBefore + 100 * 10 ** 18, "Bob should receive 100 tokens");
    }

    // BE-5: Test Action 3 - Call increment() of Counter contract twice
    function test_IncrementCounterTwice() public {
        assertEq(counter.number(), 0);

        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](2);
        calls[0] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});
        calls[1] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(counter.number(), 2, "Counter should be 2 after two increments");
    }

    // BE-5: Test all three actions batched together
    function test_BatchAllThreeActions() public {
        uint256 bobBalanceBefore = bob.balance;
        uint256 bobTokensBefore = token.balanceOf(bob);
        assertEq(counter.number(), 0);

        bytes memory transferData = abi.encodeWithSelector(token.transfer.selector, bob, 100 * 10 ** 18);
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](4);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});
        calls[1] = BatchCallDelegation7702.Call({to: address(token), value: 0, data: transferData});
        calls[2] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});
        calls[3] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(bob.balance, bobBalanceBefore + 0.01 ether, "ETH transfer failed");
        assertEq(token.balanceOf(bob), bobTokensBefore + 100 * 10 ** 18, "Token transfer failed");
        assertEq(counter.number(), 2, "Counter should be 2");
    }

    // ==================== Revert & Error Tests ====================

    // BE-1: Revert with specific CallFailed error
    function test_RevertOnFailedCall() public {
        bytes memory transferData = abi.encodeWithSelector(token.transfer.selector, bob, 2_000_000 * 10 ** 18);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(token), value: 0, data: transferData});

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                BatchCallDelegation7702.CallFailed.selector,
                0,
                abi.encodeWithSignature("Error(string)", "Insufficient balance")
            )
        );
        batchCaller.execute(calls);
    }

    // Test value > balance reverts
    function test_RevertIfValueExceedsBalance() public {
        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 100 ether, data: ""});

        vm.prank(deployer);
        vm.expectRevert();
        batchCaller.execute(calls);
    }

    // ==================== Event Tests ====================

    function test_EmitsEventsPerCall() public {
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](2);
        calls[0] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});
        calls[1] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        vm.expectEmit(true, true, false, true);
        emit CallExecuted(0, address(counter), 0, incrementData);
        vm.expectEmit(true, true, false, true);
        emit CallExecuted(1, address(counter), 0, incrementData);

        vm.prank(deployer);
        batchCaller.execute(calls);
    }

    function test_AcceptETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(batchCaller).call{value: 0.5 ether}("");
        assertTrue(success, "Contract should accept ETH");
        assertEq(address(batchCaller).balance, 10.5 ether);
    }

    // ==================== Security Tests ====================

    function test_ReentrancyViaMaliciousTarget() public {
        ReentrantAttacker attacker = new ReentrantAttacker(address(batchCaller));
        vm.deal(address(batchCaller), 10 ether);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(attacker), value: 0.01 ether, data: ""});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertTrue(attacker.attackCount() > 0, "Reentrancy was possible - documents the risk");
    }

    function test_SendETHToAddressZeroBurnsETH() public {
        uint256 contractBalanceBefore = address(batchCaller).balance;

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(0), value: 0.01 ether, data: ""});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(address(batchCaller).balance, contractBalanceBefore - 0.01 ether);
        assertEq(address(0).balance, 0.01 ether);
    }

    function test_SelfCallToContractItself() public {
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory innerCalls = new BatchCallDelegation7702.Call[](1);
        innerCalls[0] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        bytes memory executeData = abi.encodeWithSelector(batchCaller.execute.selector, innerCalls);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(batchCaller), value: 0, data: executeData});

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(counter.number(), 1, "Self-call should succeed and increment counter");
    }

    function test_LargeCallsArray() public {
        uint256 largeLength = 100;
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](largeLength);
        for (uint256 i = 0; i < largeLength; i++) {
            calls[i] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});
        }

        vm.prank(deployer);
        batchCaller.execute(calls);

        assertEq(counter.number(), largeLength, "Counter should equal calls length");
    }

    function test_EmptyCallsArray() public {
        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](0);

        vm.prank(deployer);
        batchCaller.execute(calls);
    }

    function test_AnyoneCanCallExecuteAndDrainFunds() public {
        address attacker = makeAddr("attacker");
        uint256 contractBalance = address(batchCaller).balance;

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: attacker, value: contractBalance, data: ""});

        vm.prank(attacker);
        batchCaller.execute(calls);

        assertEq(address(batchCaller).balance, 0, "Contract should be drained");
        assertEq(attacker.balance, contractBalance, "Attacker should have all ETH");
    }

    // ==================== EIP-7702 Delegation Mechanism Tests ====================

    // Test the canonical EIP-7702 self-call pattern:
    // In real 7702, the EOA sends a tx to itself (msg.sender == address(this)).
    // This test simulates that by using vm.etch + vm.prank(eoa) to call the delegated EOA.
    function test_EIP7702SelfCallPattern() public {
        // EOA that will delegate
        address eoa = makeAddr("delegatingEOA");
        vm.deal(eoa, 5 ether);

        // Simulate EIP-7702: set the EOA's code to BatchCallDelegation7702's runtime code
        bytes memory contractCode = address(batchCaller).code;
        vm.etch(eoa, contractCode);

        BatchCallDelegation7702 delegatedEOA = BatchCallDelegation7702(payable(eoa));

        // Build batch calls
        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](2);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);
        calls[1] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        // In real EIP-7702, the EOA sends a transaction TO ITSELF calling execute().
        // This means msg.sender == tx.origin == the EOA address.
        // We simulate this with vm.prank(eoa) — the EOA calls its own execute().
        vm.prank(eoa);
        delegatedEOA.execute(calls);

        assertEq(bob.balance, 0.01 ether, "Bob should receive ETH from delegated EOA");
        assertEq(counter.number(), 1, "Counter should be incremented via delegated EOA");
        assertEq(eoa.balance, 5 ether - 0.01 ether, "EOA balance should decrease");
    }

    // Test that msg.sender == address(this) access-control guard pattern works.
    // This is the canonical 7702 pattern to prevent third-party calls.
    function test_EIP7702AccessControlGuard() public {
        address eoa = makeAddr("delegatingEOA");
        vm.deal(eoa, 5 ether);

        bytes memory contractCode = address(batchCaller).code;
        vm.etch(eoa, contractCode);

        BatchCallDelegation7702 delegatedEOA = BatchCallDelegation7702(payable(eoa));

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});

        // Self-call (msg.sender == eoa == address(delegatedEOA)): the canonical flow
        vm.prank(eoa);
        delegatedEOA.execute(calls);
        assertEq(bob.balance, 0.01 ether, "Self-call should succeed");

        // Third-party call (msg.sender != address(delegatedEOA)):
        // Without an explicit guard, this also succeeds — demonstrating why
        // production 7702 contracts MUST add `require(msg.sender == address(this))`
        address thirdParty = makeAddr("thirdParty");
        calls[0] = BatchCallDelegation7702.Call({to: thirdParty, value: 0.01 ether, data: ""});

        vm.prank(thirdParty);
        delegatedEOA.execute(calls);
        // Third party succeeded — this documents the vulnerability without the guard
        assertEq(thirdParty.balance, 0.01 ether, "Without guard, third-party calls succeed");
    }

    // Test that delegation persistence: code remains after execution
    function test_EIP7702DelegationPersistence() public {
        address eoa = makeAddr("delegatingEOA");
        vm.deal(eoa, 5 ether);

        bytes memory contractCode = address(batchCaller).code;
        vm.etch(eoa, contractCode);

        // Verify code is set
        assertTrue(eoa.code.length > 0, "EOA should have code after delegation");

        // Execute a call
        BatchCallDelegation7702 delegatedEOA = BatchCallDelegation7702(payable(eoa));
        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});

        vm.prank(eoa);
        delegatedEOA.execute(calls);

        // Code persists after execution (delegation is not revoked by a single tx)
        assertTrue(eoa.code.length > 0, "Code should persist after execution");
    }

    // Test revocation pattern: signing delegation to address(0) clears code
    function test_EIP7702Revocation() public {
        address eoa = makeAddr("delegatingEOA");
        vm.deal(eoa, 5 ether);

        // Set delegation
        bytes memory contractCode = address(batchCaller).code;
        vm.etch(eoa, contractCode);
        assertTrue(eoa.code.length > 0, "Should have code");

        // Execute works while delegated
        BatchCallDelegation7702 delegatedEOA = BatchCallDelegation7702(payable(eoa));
        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: bob, value: 0.01 ether, data: ""});

        vm.prank(eoa);
        delegatedEOA.execute(calls);
        assertEq(bob.balance, 0.01 ether, "Should work while delegated");

        // Revoke delegation by clearing code (simulates signing authorization to address(0))
        vm.etch(eoa, "");
        assertEq(eoa.code.length, 0, "Code should be cleared after revocation");

        // After revocation, the EOA has no code — it's a plain EOA again.
        // Any function selector call won't match any code and will just succeed with empty return.
        // The key point: the contract logic is gone, so execute() no longer runs.
        // We verify this by checking that a batch call to transfer ETH does NOT execute.
        uint256 bobBalanceBefore = bob.balance;
        (bool success,) = eoa.call(
            abi.encodeWithSelector(
                BatchCallDelegation7702.execute.selector,
                calls
            )
        );
        // Low-level call to codeless address returns true (EVM behavior) but does nothing
        assertTrue(success, "Call to codeless address returns true (EVM quirk)");
        // But the execute() logic did NOT run — bob's balance unchanged
        assertEq(bob.balance, bobBalanceBefore, "Execute logic should not run after revocation");
    }

    // Test nonce/replay: same batch can be called multiple times (no built-in replay protection)
    function test_EIP7702NoBuiltInReplayProtection() public {
        address eoa = makeAddr("delegatingEOA");
        vm.deal(eoa, 5 ether);

        bytes memory contractCode = address(batchCaller).code;
        vm.etch(eoa, contractCode);

        BatchCallDelegation7702 delegatedEOA = BatchCallDelegation7702(payable(eoa));
        bytes memory incrementData = abi.encodeWithSelector(counter.increment.selector);

        BatchCallDelegation7702.Call[] memory calls = new BatchCallDelegation7702.Call[](1);
        calls[0] = BatchCallDelegation7702.Call({to: address(counter), value: 0, data: incrementData});

        // Execute the same batch twice — no nonce protection at contract level
        // (replay protection comes from the Ethereum tx nonce, not the contract)
        vm.prank(eoa);
        delegatedEOA.execute(calls);
        assertEq(counter.number(), 1);

        vm.prank(eoa);
        delegatedEOA.execute(calls);
        assertEq(counter.number(), 2, "Same batch can execute again - tx nonce provides replay protection");
    }
}
