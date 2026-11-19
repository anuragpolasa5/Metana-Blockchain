// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for the UnstoppableLender pool
interface IUnstoppableLender {
    function flashLoan(uint256 borrowAmount) external;
}

/// @title ReceiverUnstoppable
/// @author Damn Vulnerable DeFi (modified for Echidna exercise)
/// @notice A contract that receives flash loans from UnstoppableLender.
/// @dev Implements the receiveTokens callback to return borrowed tokens.
contract ReceiverUnstoppable {
    /// @notice The lending pool this receiver interacts with
    IUnstoppableLender private immutable pool;

    /// @notice The owner who can trigger flash loans
    address private immutable owner;

    /// @notice Initializes the receiver with its pool and sets the owner
    /// @param poolAddress The address of the UnstoppableLender pool
    constructor(address poolAddress) {
        pool = IUnstoppableLender(poolAddress);
        owner = msg.sender;
    }

    /// @notice Callback function called by the pool during flash loan execution
    /// @dev Returns all borrowed tokens back to the pool
    /// @param tokenAddress The address of the borrowed token
    /// @param amount The amount of tokens to return
    function receiveTokens(address tokenAddress, uint256 amount) external {
        require(msg.sender == address(pool), "Sender must be pool");
        require(
            IERC20(tokenAddress).transfer(msg.sender, amount),
            "Transfer of tokens failed"
        );
    }

    /// @notice Initiates a flash loan from the pool
    /// @dev Only callable by the contract owner
    /// @param amount The amount of tokens to borrow
    function executeFlashLoan(uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        pool.flashLoan(amount);
    }
}
