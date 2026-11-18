// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CommunityToken.sol";

/**
 * @title RewardsVault
 * @notice Accepts ETH donations, mints CommunityToken rewards at a fixed rate,
 *         and allows a treasurer to withdraw pooled ETH to a foundation wallet.
 *
 * Roles
 * ─────
 * DEFAULT_ADMIN_ROLE → granted to `admin`; can grant/revoke all roles and update
 *                      the foundation wallet
 * PAUSER_ROLE        → may pause / unpause this contract
 * AUDITOR_ROLE       → alias for PAUSER_ROLE (same bytes32 value)
 * TREASURER_ROLE     → may withdraw ETH to the foundation wallet
 *
 * No Ownable is used; all access is enforced exclusively via AccessControl.
 */
contract RewardsVault is AccessControl, Pausable, ReentrancyGuard {
    // ─────────────────────────────────────────────────────────── roles ──────
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE"); // RV-3
    bytes32 public constant PAUSER_ROLE    = keccak256("PAUSER_ROLE");    // RV-3

    /// @notice AUDITOR_ROLE is an alias for PAUSER_ROLE (RV-3).
    ///         Auditors receive identical on-chain authority: pause/unpause only.
    bytes32 public constant AUDITOR_ROLE   = PAUSER_ROLE;                 // RV-3

    // ─────────────────────────────────────────────────────────── constants ──
    /**
     * @notice Token exchange rate: 1 CommunityToken per 0.01 ETH. (RV-4)
     *
     *   tokens = msg.value * 1e18 / RATE
     *
     *   RATE is the ETH price per token: 0.01 ether (1e16 wei).
     *
     *   Example: 0.05 ETH (5e16 wei)
     *     tokens = 5e16 * 1e18 / 1e16 = 5e18 = 5 tokens ✓
     */
    uint256 public constant RATE = 0.01 ether;

    // ─────────────────────────────────────────────────────────── state ──────
    CommunityToken public immutable token;

    address public foundationWallet;

    // ─────────────────────────────────────────────────────────── events ──────
    event Donation(address indexed donor, uint256 ethAmount, uint256 tokensMinted);
    event Withdrawal(address indexed to, uint256 amount);
    event FoundationWalletUpdated(address indexed oldWallet, address indexed newWallet);

    // ────────────────────────────────────────────────── custom errors ────────
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error DirectTransferNotAllowed();

    // ──────────────────────────────────────────────────────── constructor ───
    /**
     * @param token_           Address of the deployed CommunityToken contract
     * @param admin            Receives DEFAULT_ADMIN_ROLE and PAUSER_ROLE (RV-2)
     * @param foundationWallet_ Initial foundation wallet address
     */
    constructor(
        CommunityToken token_,
        address admin,
        address foundationWallet_
    ) {
        if (address(token_) == address(0)) revert ZeroAddress();
        if (admin == address(0))           revert ZeroAddress();
        if (foundationWallet_ == address(0)) revert ZeroAddress();

        token           = token_;
        foundationWallet = foundationWallet_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin); // RV-2
        _grantRole(PAUSER_ROLE, admin);         // RV-2
    }

    // ────────────────────────────────────────────────────── core: donate ────
    /**
     * @notice Donate ETH and receive CommunityToken rewards. (RV-5)
     * @dev    1 token per 0.01 ETH.  Contract must not be paused.
     *         Emits {Donation}.
     */
    function donate() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();

        uint256 tokensToMint = (msg.value * 1e18) / RATE;
        token.mint(msg.sender, tokensToMint);

        emit Donation(msg.sender, msg.value, tokensToMint);
    }

    // ─────────────────────────────────────────────────── core: withdraw ─────
    /**
     * @notice Withdraw `amount` wei to the foundation wallet. (RV-6)
     * @dev    Caller must hold TREASURER_ROLE.
     *         Uses a low-level call for ETH transfer (RV-10).
     *         Emits {Withdrawal}.
     */
    function withdraw(uint256 amount)
        external
        onlyRole(TREASURER_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert InsufficientBalance(amount, address(this).balance);

        address payable dest = payable(foundationWallet);
        (bool ok, ) = dest.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawal(dest, amount);
    }

    // ──────────────────────────────────────── admin: set foundation wallet ──
    /**
     * @notice Update the foundation wallet address. (RV-7)
     * @dev    Caller must hold DEFAULT_ADMIN_ROLE.  Zero address reverts.
     */
    function setFoundationWallet(address newWallet)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newWallet == address(0)) revert ZeroAddress();
        emit FoundationWalletUpdated(foundationWallet, newWallet);
        foundationWallet = newWallet;
    }

    // ─────────────────────────────────────────────────────────── pausing ────
    /// @notice Pause the vault — callable by PAUSER_ROLE or AUDITOR_ROLE. (RV-8)
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the vault — callable by PAUSER_ROLE or AUDITOR_ROLE. (RV-8)
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────── block accidental ETH transfers ─────
    /**
     * @dev Plain ETH transfers (without calldata) are explicitly rejected. (RV-9)
     */
    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    /**
     * @dev Calls with unknown calldata are explicitly rejected. (RV-9)
     */
    fallback() external payable {
        revert DirectTransferNotAllowed();
    }
}
