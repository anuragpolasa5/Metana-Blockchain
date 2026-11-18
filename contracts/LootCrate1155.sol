// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title LootCrate1155 – ERC-1155 loot-crate shop for a video-game economy.
///
/// Token ID layout:
///   1 = Sword  (fungible, max 5 000 total supply)
///   2 = Shield (fungible, max 5 000 total supply)
///   3+ = Cosmetic NFTs (non-fungible style, max supply 1 each; IDs auto-increment)
///
/// Players call `openCrate(count)` and pay 0.02 ETH per crate.  A pseudorandom
/// keccak256 roll decides whether the crate yields swords, shields, or a cosmetic.
/// All items in a single crate are minted in one `_mintBatch` call.
///
/// PAUSER_ROLE can halt crate openings instantly and resume later.
/// MINTER_ROLE can airdrop arbitrary batches without payment.
contract LootCrate1155 is ERC1155, AccessControl, Pausable {
    using Strings for uint256;

    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ─── Token IDs & supply caps ──────────────────────────────────────────────
    uint256 public constant SWORD_ID    = 1;
    uint256 public constant SHIELD_ID   = 2;
    uint256 public constant MAX_FUNGIBLE_SUPPLY = 5_000; // per ID (1 and 2)

    uint256 public constant CRATE_PRICE = 0.02 ether;

    // Next cosmetic ID (starts at 3; increments for each unique cosmetic minted)
    uint256 private _nextCosmeticId = 3;

    // Total minted per token ID (used to enforce supply caps)
    mapping(uint256 => uint256) public totalMinted;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error InsufficientPayment(uint256 sent, uint256 required);
    error SupplyCapExceeded(uint256 tokenId, uint256 available, uint256 requested);
    error WithdrawFailed();
    error ZeroCrateCount();
    error ZeroAdminAddress();
    error RefundFailed();
    /// @dev Emitted when a MINTER_ROLE tries to re-mint an already-issued cosmetic ID.
    error CosmeticDuplicateMint(uint256 tokenId);
    /// @dev Emitted when a MINTER_ROLE tries to mint a cosmetic with amount != 1.
    error CosmeticAmountNotOne(uint256 tokenId, uint256 amount);

    // ─── Events ───────────────────────────────────────────────────────────────
    event CrateOpened(address indexed player, uint256 crateCount, uint256[] ids, uint256[] amounts);
    event CosmeticMinted(address indexed to, uint256 indexed tokenId);
    /// @notice Emitted when one or more crate rolls are skipped because fungible
    ///         supply is exhausted, and the corresponding ETH is refunded.
    event SkippedRollRefund(address indexed player, uint256 skippedCount, uint256 refundAmount);

    // ─── State ────────────────────────────────────────────────────────────────
    string private _baseTokenURI;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param baseURI  Metadata base URI, e.g. `ipfs://bafy.../`.
    /// @param admin    Address granted all roles at deployment.
    constructor(string memory baseURI, address admin) ERC1155(baseURI) {
        if (admin == address(0)) revert ZeroAdminAddress();
        _baseTokenURI = baseURI;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE,        admin);
        _grantRole(PAUSER_ROLE,        admin);
    }

    // ─── URI ──────────────────────────────────────────────────────────────────

    /// @notice Returns `{baseURI}{tokenId}.json`.
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    /// @notice Update the base URI (admin only).
    function setBaseURI(string memory baseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseURI;
        // ERC-1155 does not expose a setter; emit the standard event manually
        emit URI(baseURI, type(uint256).max); // sentinel: all IDs
    }

    // ─── Crate opening ────────────────────────────────────────────────────────

    /// @notice Open `count` crates. Costs 0.02 ETH each.
    ///         Mints a pseudorandom assortment: typically swords/shields and,
    ///         with low probability (~10 %), a one-of-one cosmetic NFT.
    /// @dev Pseudorandomness via keccak256 is sufficient for a game loot box;
    ///      it should NOT be used where economic exploitability matters.
    function openCrate(uint256 count) external payable whenNotPaused {
        if (count == 0) revert ZeroCrateCount();

        uint256 required = CRATE_PRICE * count;
        if (msg.value != required) revert InsufficientPayment(msg.value, required);

        // We build arrays for a single _mintBatch call.
        // Worst case per crate: 3 entries (sword, shield, cosmetic); pre-allocate.
        uint256[] memory ids     = new uint256[](count * 3);
        uint256[] memory amounts = new uint256[](count * 3);
        uint256 idx;
        uint256 skipped; // crate rolls that minted nothing (fungible cap exhausted)

        for (uint256 i; i < count; ) {
            // Pseudorandom seed: sender + timestamp + i
            uint256 roll = uint256(
                keccak256(abi.encodePacked(msg.sender, block.timestamp, i))
            ) % 100; // 0-99

            if (roll < 10) {
                // 10 % chance: cosmetic NFT (unique, supply = 1)
                uint256 cosmeticId = _nextCosmeticId;
                unchecked { _nextCosmeticId++; }
                ids[idx]     = cosmeticId;
                amounts[idx] = 1;
                totalMinted[cosmeticId] = 1;
                unchecked { idx++; }
                emit CosmeticMinted(msg.sender, cosmeticId);
            } else if (roll < 55) {
                // 45 % chance: 1 Sword
                if (_checkAndAccumulateFungible(SWORD_ID, 1, ids, amounts, idx)) {
                    unchecked { idx++; }
                } else {
                    // Fungible cap exhausted — count this roll as skipped
                    unchecked { skipped++; }
                }
            } else {
                // 45 % chance: 1 Shield
                if (_checkAndAccumulateFungible(SHIELD_ID, 1, ids, amounts, idx)) {
                    unchecked { idx++; }
                } else {
                    // Fungible cap exhausted — count this roll as skipped
                    unchecked { skipped++; }
                }
            }

            unchecked { i++; }
        }

        // Trim arrays to actual length
        assembly {
            mstore(ids, idx)
            mstore(amounts, idx)
        }

        // If any fungible caps were exhausted, refund the corresponding ETH so
        // users are never charged for crates that yielded nothing.
        if (skipped > 0) {
            uint256 refund = CRATE_PRICE * skipped;
            emit SkippedRollRefund(msg.sender, skipped, refund);
            (bool ok, ) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed();
        }

        _mintBatch(msg.sender, ids, amounts, "");
        emit CrateOpened(msg.sender, count, ids, amounts);
    }

    // ─── Airdrop (MINTER_ROLE) ────────────────────────────────────────────────

    /// @notice Airdrop arbitrary items to `to` without payment. Only MINTER_ROLE.
    /// @dev    Enforces the same invariants as `openCrate`:
    ///         - Fungible IDs (1, 2): capped at MAX_FUNGIBLE_SUPPLY each.
    ///         - Cosmetic IDs (>= 3): must be unique (supply = 1 each);
    ///           `amount` must equal 1 and the ID must not have been minted before.
    ///           `_nextCosmeticId` is advanced whenever a new cosmetic ID is airdropped
    ///           so that subsequent `openCrate` cosmetic rolls never collide.
    function mintBatch(
        address         to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) {
        for (uint256 i; i < ids.length; ) {
            uint256 id  = ids[i];
            uint256 amt = amounts[i];

            if (id == SWORD_ID || id == SHIELD_ID) {
                // ── Fungible cap check ────────────────────────────────────────
                uint256 available = MAX_FUNGIBLE_SUPPLY - totalMinted[id];
                if (amt > available) revert SupplyCapExceeded(id, available, amt);
                unchecked { totalMinted[id] += amt; }
            } else {
                // ── Cosmetic uniqueness invariant (ID >= 3) ───────────────────
                // Each cosmetic must be minted exactly once (supply-1 NFT style).
                if (amt != 1) revert CosmeticAmountNotOne(id, amt);
                if (totalMinted[id] != 0) revert CosmeticDuplicateMint(id);

                totalMinted[id] = 1;

                // Keep _nextCosmeticId ahead of any explicitly supplied cosmetic ID
                // so that openCrate's auto-increment counter never collides with an
                // airdropped cosmetic.
                if (id >= _nextCosmeticId) {
                    _nextCosmeticId = id + 1;
                }

                emit CosmeticMinted(to, id);
            }

            unchecked { i++; }
        }
        _mintBatch(to, ids, amounts, "");
    }

    // ─── Pause ────────────────────────────────────────────────────────────────

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─── Admin withdrawal ─────────────────────────────────────────────────────

    /// @notice Withdraw accumulated ETH from crate sales.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        if (!ok) revert WithdrawFailed();
    }

    // ─── Overrides ────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Writes a fungible mint into the arrays, checking supply cap.
    ///      Returns true if an entry was written, false if the cap was exhausted
    ///      (caller must NOT advance its index when false is returned).
    function _checkAndAccumulateFungible(
        uint256   id,
        uint256   amount,
        uint256[] memory idsArr,
        uint256[] memory amountsArr,
        uint256   slot
    ) internal returns (bool written) {
        uint256 available = MAX_FUNGIBLE_SUPPLY - totalMinted[id];
        if (available == 0) {
            // Cap reached — silently skip; do NOT write id=0/amount=0 into arrays
            return false;
        }
        uint256 actual = amount > available ? available : amount;
        totalMinted[id] += actual;
        idsArr[slot]     = id;
        amountsArr[slot] = actual;
        return true;
    }
}