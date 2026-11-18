// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LearnToken.sol";

/**
 * @title TokenSale
 * @notice Buy and sell LearnToken (LRN) in exchange for ETH.
 *
 * FE-4  – Inherits Ownable2Step; owner can withdraw tokens and ETH.
 * FE-5  – Constructor sets token address, buyPrice, sellPrice.
 * FE-6  – This contract must be granted MINTER_ROLE in LearnToken after deployment.
 * FE-7  – buyTokens() (and receive()) let users purchase tokens. Reserves are used
 *          first; new tokens are minted only when reserves run out. Reverts if
 *          buying would exceed MAX_SUPPLY.
 * FE-8  – sellTokens() transfers tokens to this contract (adding to reserves) and
 *          sends the user ETH.
 * FE-9  – withdrawTokens() lets the owner retrieve ERC20 tokens.
 * FE-10 – withdrawETH() lets the owner retrieve ETH.
 */
contract TokenSale is Ownable2Step {
    // ────────────────────────────────────────────────────────────────────────
    // State
    // ────────────────────────────────────────────────────────────────────────

    /// @notice The ERC20 token being sold.
    LearnToken public immutable token;

    /// @notice Price a user pays per whole token (in wei).
    uint256 public immutable buyPrice;

    /// @notice Price a user receives per whole token when selling (in wei).
    uint256 public immutable sellPrice;

    // ────────────────────────────────────────────────────────────────────────
    // Events
    // ────────────────────────────────────────────────────────────────────────

    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 ethPaid);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 ethReceived);
    event ETHWithdrawn(address indexed owner, uint256 amount);
    event TokensWithdrawn(address indexed owner, uint256 amount);

    // ────────────────────────────────────────────────────────────────────────
    // Errors
    // ────────────────────────────────────────────────────────────────────────

    error ZeroAmount();
    error InsufficientETHSent(uint256 required, uint256 sent);
    error MaxSupplyExceeded();
    error InsufficientETHReserves(uint256 available, uint256 required);
    error InsufficientTokenBalance(uint256 available, uint256 required);
    error ETHTransferFailed();
    error InvalidAddress();
    error InvalidPrice();

    // ────────────────────────────────────────────────────────────────────────
    // Constructor
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @param _token     Address of the LearnToken contract.
     * @param _sellPrice Price in wei per token that users RECEIVE when selling.
     * @param _buyPrice  Price in wei per token that users PAY when buying.
     * @param _owner     Address that will be the initial owner of this contract.
     *
     * @dev  Ownership is set to _owner via Ownable2Step's constructor.
     *       After deployment the deployer must call:
     *         learnToken.grantRole(MINTER_ROLE, address(tokenSale));
     */
    constructor(address _token, uint256 _sellPrice, uint256 _buyPrice, address _owner)
        Ownable(_owner)
    {
        if (_token == address(0)) revert InvalidAddress();
        if (_owner == address(0)) revert InvalidAddress();
        if (_buyPrice == 0 || _sellPrice == 0) revert InvalidPrice();
        if (_sellPrice >= _buyPrice) revert InvalidPrice(); // sell < buy to maintain spread

        token = LearnToken(_token);
        buyPrice = _buyPrice;
        sellPrice = _sellPrice;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Buy tokens
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @notice Buy tokens by sending ETH.
     * @dev    The number of tokens is calculated from msg.value and buyPrice.
     *         Reserves are consumed before minting.
     *         Reverts if msg.value is not an exact multiple of buyPrice (no dust retained).
     *
     * FE-7: Use reserves first; mint only if needed; revert if cap exceeded.
     */
    function buyTokens() public payable {
        if (msg.value == 0) revert ZeroAmount();

        uint256 decimalsVal = 10 ** token.decimals();

        // Enforce exact-price multiples – no residual ETH silently retained
        if ((msg.value * decimalsVal) % buyPrice != 0) {
            revert InsufficientETHSent(buyPrice, msg.value);
        }

        // Calculate whole token amount (tokens are 18-decimal; prices are per whole token)
        uint256 tokenAmount = (msg.value * decimalsVal) / buyPrice;
        if (tokenAmount == 0) revert ZeroAmount();

        uint256 contractReserve = token.balanceOf(address(this));

        // FE-16 guard: only the portion that must be freshly minted counts against the cap.
        // Tokens already held by this contract (reserves) do not increase total supply.
        uint256 mintAmount = tokenAmount > contractReserve ? tokenAmount - contractReserve : 0;

        uint256 totalSupply = token.totalSupply();
        uint256 maxSup = token.maxSupply();

        if (totalSupply + mintAmount > maxSup) {
            revert MaxSupplyExceeded();
        }

        if (contractReserve >= tokenAmount) {
            require(token.transfer(msg.sender, tokenAmount), "Transfer failed");
        } else {
            if (contractReserve > 0) {
                require(token.transfer(msg.sender, contractReserve), "Transfer failed");
            }

            token.mint(
                msg.sender,
                tokenAmount - contractReserve
            );
        }

        emit TokensPurchased(msg.sender, tokenAmount, msg.value);
    }

    /**
     * @notice Fallback: purchasing tokens by sending ETH directly to the contract.
     *
     * FE-7: Direct ETH sends are forwarded to buyTokens().
     */
    receive() external payable {
        buyTokens();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Sell tokens
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @notice Sell `tokenAmount` (in token wei) back to the contract for ETH.
     *
     * FE-8: Tokens are transferred to this contract (building reserves);
     *        the equivalent ETH is sent to the seller.
     *        The caller must have approved this contract to spend their tokens first.
     *
     * FE-17: Reverts if contract ETH balance is insufficient.
     *
     * @param tokenAmount  Amount of tokens (in wei, i.e. 10**18 per whole token).
     */
    function sellTokens(uint256 tokenAmount) external {
        if (tokenAmount == 0) revert ZeroAmount();

        uint256 ethAmount = (tokenAmount * sellPrice) / (10 ** token.decimals());
        if (ethAmount == 0) revert ZeroAmount();

        // FE-17: check contract ETH balance
        if (address(this).balance < ethAmount) {
            revert InsufficientETHReserves(address(this).balance, ethAmount);
        }

        // Pull tokens into this contract (adds to reserves for future buyers)
        bool ok = token.transferFrom(msg.sender, address(this), tokenAmount);
        require(ok, "TransferFrom failed");

        // Send ETH to seller
        (bool sent, ) = payable(msg.sender).call{value: ethAmount}("");
        if (!sent) revert ETHTransferFailed();

        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Owner withdrawals
    // ────────────────────────────────────────────────────────────────────────

    /**
     * @notice Withdraw ERC20 tokens held by this contract.
     * @param amount  Token amount in wei (use type(uint256).max to withdraw all).
     *
     * FE-9
     */
    function withdrawTokens(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = token.balanceOf(address(this));

        // Sentinel: type(uint256).max means "withdraw everything"
        uint256 withdrawAmount = amount == type(uint256).max ? balance : amount;

        if (balance < withdrawAmount) revert InsufficientTokenBalance(balance, withdrawAmount);

        bool ok = token.transfer(owner(), withdrawAmount);
        require(ok, "Transfer failed");

        emit TokensWithdrawn(owner(), withdrawAmount);
    }

    /**
     * @notice Withdraw ETH from this contract.
     * @param amount  ETH amount in wei (use type(uint256).max to withdraw all).
     *
     * FE-10
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = address(this).balance;

        // Sentinel: type(uint256).max means "withdraw everything"
        uint256 withdrawAmount = amount == type(uint256).max ? balance : amount;

        if (balance < withdrawAmount) revert InsufficientETHReserves(balance, withdrawAmount);

        (bool sent, ) = payable(owner()).call{value: withdrawAmount}("");
        if (!sent) revert ETHTransferFailed();

        emit ETHWithdrawn(owner(), withdrawAmount);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Views
    // ────────────────────────────────────────────────────────────────────────

    /// @notice ETH balance held by this contract.
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Token reserve balance held by this contract.
    function tokenReserve() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
