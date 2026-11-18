// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * CrystalDAO – Challenge 7
 *
 * A minimal-proxy (ERC-1167) treasury factory used by the Crystal DAO.
 * The implementation contract stores the admin in its own storage during the
 * constructor.  Because ERC-1167 clones execute via DELEGATECALL the clone
 * shares storage layout with the implementation, BUT the constructor of the
 * implementation runs in the IMPLEMENTATION'S context, not the clone's.
 *
 * ─── The Bug ─────────────────────────────────────────────────────────────────
 *
 * CrystalTreasuryImpl stores `admin` in slot 0 inside its constructor.
 * That write lands in the IMPLEMENTATION contract's slot 0, not the clone's.
 *
 * The clone is deployed via Clones.clone(), which copies the runtime bytecode
 * but starts with zeroed storage. The clone then calls initialize(admin), but
 * initialize() checks `if (_initialized) revert AlreadyInitialized()`.
 *
 * Wait — that check looks at the CLONE's slot 1 (still false). So initialize()
 * should work... unless initialize() was already front-run by an attacker, OR
 * the DAO admin forgot to call initialize() and the factory did NOT call it.
 *
 * ─── Actual Vulnerability ────────────────────────────────────────────────────
 *
 * CrystalTreasuryFactory deploys the clone but NEVER calls initialize().
 * The admin slot on the clone is therefore address(0).
 *
 * The withdraw() function performs:
 *   require(msg.sender == admin, "not admin");
 * where admin == address(0) → no EOA can ever satisfy this.
 *
 * However, initialize() is UNPROTECTED on the clone (the guard only reverts
 * if _initialized == true, which is false for our clone).
 *
 * ─── Rescue ──────────────────────────────────────────────────────────────────
 *
 * 1. Call clone.initialize(whitehat) → sets admin = whitehat in clone's slot 0.
 * 2. Call clone.withdraw(whitehat, 100 ether) → transfers 100 ETH to whitehat.
 *
 * This is safe / intended because:
 *  - The vulnerability is a missing initializer call by the factory.
 *  - Our "attack" is calling the public initializer on an uninitialised clone.
 */

// ─── Implementation ──────────────────────────────────────────────────────────

/// @title CrystalTreasuryImpl
/// @author Challenge 7
/// @notice Implementation contract for the Crystal DAO treasury.
/// @dev Contains the uninitialised clone vulnerability — constructor sets state
///      in the implementation's storage, not in any clone's storage.
contract CrystalTreasuryImpl {
    /// @notice The admin address with withdrawal privileges.
    /// @dev Slot 0: In the implementation this is set by the constructor.
    ///      In a clone this starts as address(0) because clones have zeroed storage.
    address public admin;

    /// @dev Guard against double-initialisation (slot 1).
    bool private _initialized;

    /// @notice Emitted when admin is set via initialize().
    /// @param admin The address set as admin.
    event AdminSet(address indexed admin);

    /// @notice Emitted when ETH is withdrawn from the treasury.
    /// @param to The recipient address.
    /// @param amount The amount of ETH withdrawn.
    event Withdrawn(address indexed to, uint256 amount);

    /// @dev Reverts when initialize() is called on an already-initialized contract.
    error AlreadyInitialized();
    /// @dev Reverts when a non-admin calls withdraw().
    error NotAdmin();
    /// @dev Reverts when withdrawal amount exceeds contract balance.
    error InsufficientBalance();
    /// @dev Reverts when the ETH transfer fails.
    error TransferFailed();

    /// @notice Constructs the implementation and sets msg.sender as admin.
    /// @dev This runs in the IMPLEMENTATION's storage context only.
    ///      Clone storage is NOT touched here — this is the root cause of the vulnerability.
    constructor() {
        admin = msg.sender;
        _initialized = true;
    }

    /// @notice Initialise the clone's admin. Callable only when _initialized is false.
    /// @dev VULNERABILITY: On uninitialised clones, _initialized = false and admin = address(0),
    ///      allowing anyone to call this and claim admin rights.
    /// @param _admin The address to set as admin of this clone.
    function initialize(address _admin) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        admin = _admin;
        emit AdminSet(_admin);
    }

    /// @notice Withdraw ETH from the treasury. Restricted to admin.
    /// @dev After exploiting initialize(), the attacker can drain all funds.
    /// @param to The payable address to receive the withdrawn ETH.
    /// @param amount The amount of ETH in wei to withdraw.
    function withdraw(address payable to, uint256 amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (amount > address(this).balance) revert InsufficientBalance();
        emit Withdrawn(to, amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Allows the contract to receive ETH.
    receive() external payable {}
}

// ─── Factory ─────────────────────────────────────────────────────────────────

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title CrystalTreasuryFactory
/// @author Challenge 7
/// @notice Factory that deploys ERC-1167 minimal proxy clones of CrystalTreasuryImpl.
/// @dev BUG: deployTreasury() never calls initialize() on the clone, leaving admin = address(0).
contract CrystalTreasuryFactory {
    /// @notice The implementation contract address that clones delegate to.
    address public immutable implementation;

    /// @notice Emitted when a new treasury clone is deployed.
    /// @param clone The address of the deployed clone.
    /// @param admin The intended admin (not actually set on clone due to the bug).
    event TreasuryDeployed(address indexed clone, address indexed admin);

    /// @notice Deploys the factory and creates the implementation contract.
    constructor() {
        implementation = address(new CrystalTreasuryImpl());
    }

    /// @notice Deploy a new treasury clone.
    /// @dev BUG: initialize() is never called. The clone's admin slot stays address(0).
    ///      FIX would be: CrystalTreasuryImpl(clone).initialize(msg.sender);
    /// @return clone The address of the newly deployed minimal proxy clone.
    function deployTreasury() external returns (address clone) {
        clone = Clones.clone(implementation);
        // ← Missing: CrystalTreasuryImpl(clone).initialize(msg.sender);
        emit TreasuryDeployed(clone, msg.sender);
    }
}
