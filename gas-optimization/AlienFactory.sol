// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Unoptimized Alien Contract
/// @author Module 11 Submission
/// @notice Represents an alien entity with name, power, and lifecycle state
/// @dev Intentionally uses gas-inefficient patterns for comparison with optimized version
contract Alien {
    // AF-01: Each variable occupies its own 32-byte storage slot (wasteful)
    string public name;       // Slot 0+ (dynamic)
    uint256 public power;     // Slot 1 (uses full 32 bytes for a number)
    address public owner;     // Slot 2 (20 bytes, wastes 12 bytes of slot)
    bool public isAlive;      // Slot 3 (1 byte, wastes 31 bytes of slot)

    /// @notice Creates a new Alien with the given attributes
    /// @param _name The alien's display name
    /// @param _power The alien's combat power level
    /// @param _owner The address that owns this alien
    // AF-02: Constructor uses `memory` for string (copied from calldata to memory)
    constructor(string memory _name, uint256 _power, address _owner) {
        name = _name;
        power = _power;
        owner = _owner;
        isAlive = true;
    }

    /// @notice Returns the alien's power if it is alive
    /// @dev Reverts with a string message (costly vs custom errors)
    /// @return The alien's power level
    // AF-03: Uses require with string (stores string in bytecode, expensive revert)
    function attack() external view returns (uint256) {
        require(isAlive, "Alien is dead");
        return power;
    }

    /// @notice Revives the alien (only callable by owner)
    /// @dev Reverts with a string message if caller is not owner
    function heal() external {
        require(msg.sender == owner, "Not owner");
        isAlive = true;
    }
}

/// @title Unoptimized Alien Factory
/// @author Module 11 Submission
/// @notice Factory contract that creates and tracks Alien instances
/// @dev Uses redundant storage patterns for demonstration purposes
contract AlienFactory {
    // AF-04: Stores ALL alien addresses (redundant with ownerAliens mapping)
    address[] public aliens;
    mapping(address => address[]) public ownerAliens;

    /// @notice Emitted when a new alien is created
    /// @param alien The address of the newly deployed Alien contract
    /// @param owner The address of the alien's owner
    event AlienCreated(address indexed alien, address indexed owner);

    /// @notice Creates a new Alien contract and registers it
    /// @param _name The alien's display name
    /// @param _power The alien's combat power level
    // AF-05: Uses `public` visibility (copies calldata params to memory)
    // AF-06: Performs two array pushes per creation (2x SSTORE operations)
    function createAlien(string memory _name, uint256 _power) public {
        Alien alien = new Alien(_name, _power, msg.sender);
        aliens.push(address(alien));
        ownerAliens[msg.sender].push(address(alien));
        emit AlienCreated(address(alien), msg.sender);
    }

    /// @notice Returns the total number of aliens created
    /// @return The length of the aliens array
    function getAlienCount() public view returns (uint256) {
        return aliens.length;
    }

    /// @notice Returns all alien addresses owned by a specific address
    /// @param _owner The owner address to query
    /// @return An array of alien contract addresses
    function getOwnerAliens(address _owner) public view returns (address[] memory) {
        return ownerAliens[_owner];
    }
}
