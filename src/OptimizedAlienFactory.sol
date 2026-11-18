// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Optimized Alien Contract
/// @author Module 11 Submission
/// @notice Gas-efficient alien entity with packed storage layout
/// @dev Demonstrates storage slot packing and custom errors for gas savings
contract OptimizedAlien {
    // AF-01: Pack variables into a single 32-byte storage slot
    // Layout: owner (20 bytes) + power (8 bytes) + isAlive (1 byte) = 29 bytes = 1 slot
    // Original used 4 separate slots (4x SSTORE on construction)
    address public owner;    // 20 bytes
    uint64 public power;     // 8 bytes (max ~18.4 quintillion — sufficient for power levels)
    bool public isAlive;     // 1 byte

    // Dynamic string gets its own slot(s) regardless of packing
    string public name;

    // AF-03: Custom errors save ~50-200 gas vs require strings
    // Error selector is 4 bytes vs storing/loading entire string from bytecode
    error NotAlive();
    error NotOwner();

    /// @notice Creates a new optimized Alien with packed storage writes
    /// @param _name The alien's display name
    /// @param _power The alien's combat power level (uint64 for slot packing)
    /// @param _owner The address that owns this alien
    // AF-02: Constructor still needs `memory` for internal string handling
    // but the factory passes `calldata` externally (optimization at call site)
    constructor(string memory _name, uint64 _power, address _owner) {
        name = _name;
        // AF-01: These three assignments write to the SAME storage slot
        // Solidity compiler packs them into a single SSTORE operation
        owner = _owner;
        power = _power;
        isAlive = true;
    }

    /// @notice Returns the alien's power if it is alive
    /// @dev Uses custom error for gas-efficient revert
    /// @return The alien's power level as uint64
    // AF-03: Custom error `NotAlive()` costs ~4 bytes vs "Alien is dead" string
    function attack() external view returns (uint64) {
        if (!isAlive) revert NotAlive();
        return power;
    }

    /// @notice Revives the alien (only callable by owner)
    /// @dev Uses custom error for unauthorized access
    function heal() external {
        if (msg.sender != owner) revert NotOwner();
        isAlive = true;
    }
}

/// @title Optimized Alien Factory
/// @author Module 11 Submission
/// @notice Gas-efficient factory with reduced storage writes and optimized visibility
/// @dev Eliminates redundant storage, uses calldata, external visibility, and unchecked math
contract OptimizedAlienFactory {
    // AF-04: Replace redundant address[] with a simple counter
    // Saves ~20,000 gas per creation (no array length SSTORE + no element SSTORE)
    // Trade-off: cannot enumerate all aliens on-chain (use events for indexing)
    uint256 private _alienCount;

    // Single mapping is sufficient — removed redundant aliens[] array
    mapping(address => address[]) private _ownerAliens;

    /// @notice Emitted when a new alien is created
    /// @param alien The address of the newly deployed Alien contract
    /// @param owner The address of the alien's owner
    event AlienCreated(address indexed alien, address indexed owner);

    /// @notice Creates a new optimized Alien contract
    /// @dev Uses calldata for string, external visibility, and uint64 for power
    /// @param _name The alien's display name (calldata avoids memory copy)
    /// @param _power The alien's combat power level (uint64 enables storage packing)
    // AF-05: `external` reads params from calldata directly (no memory copy)
    //         `calldata` for string avoids allocating + copying to memory
    // AF-06: Single array push instead of two — counter replaces second push
    function createAlien(string calldata _name, uint64 _power) external {
        OptimizedAlien alien = new OptimizedAlien(_name, _power, msg.sender);
        address alienAddr = address(alien);

        // Unchecked: alienCount won't overflow uint256 in any realistic scenario
        unchecked { ++_alienCount; }

        // AF-06: Only one SSTORE for array push (vs two in unoptimized)
        _ownerAliens[msg.sender].push(alienAddr);

        emit AlienCreated(alienAddr, msg.sender);
    }

    /// @notice Returns the total number of aliens created
    /// @dev Reads from a simple uint256 counter (single SLOAD)
    /// @return The total count of aliens ever created
    function getAlienCount() external view returns (uint256) {
        return _alienCount;
    }

    /// @notice Returns all alien addresses owned by a specific address
    /// @param _owner The owner address to query
    /// @return An array of alien contract addresses owned by the given address
    function getOwnerAliens(address _owner) external view returns (address[] memory) {
        return _ownerAliens[_owner];
    }
}
