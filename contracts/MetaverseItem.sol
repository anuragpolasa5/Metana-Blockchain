// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title MetaverseItem – ERC-721 NFT collection with royalties and enumeration.
/// @notice Maximum 10 000 unique tokens. Token URIs are constructed as
///         `{baseURI}{tokenId}.json`. A fixed 5 % (500 bps) royalty is embedded
///         via ERC-2981 and routes to the creator address supplied at deployment.
contract MetaverseItem is ERC721, ERC721Enumerable, ERC721Royalty, AccessControl {
    using Strings for uint256;
    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");

    // ─── State ────────────────────────────────────────────────────────────────
    uint256 public constant MAX_SUPPLY = 10_000;

    uint256 private _nextTokenId = 1;  // starts at 1; ID 0 is never minted
    string  private _baseTokenURI;
    bool    private _baseURILocked;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error MaxSupplyReached();
    error BaseURILocked();
    error ZeroAdminAddress();

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param name     Collection name.
    /// @param symbol   Collection symbol.
    /// @param baseURI  Initial IPFS base URI, e.g. `ipfs://bafy.../`.
    /// @param admin    Address granted DEFAULT_ADMIN_ROLE, ADMIN_ROLE, and MINTER_ROLE.
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address admin
    ) ERC721(name, symbol) {
        if (admin == address(0)) revert ZeroAdminAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE,         admin);
        _grantRole(MINTER_ROLE,        admin);

        _baseTokenURI = baseURI;
        _setDefaultRoyalty(admin, 500); // 5 % = 500 basis points
    }

    // ─── Minting ──────────────────────────────────────────────────────────────

    /// @notice Mint the next token to `to`. Reverts if max supply is reached.
    function mint(address to) external onlyRole(MINTER_ROLE) {
        if (_nextTokenId > MAX_SUPPLY) revert MaxSupplyReached();
        uint256 tokenId = _nextTokenId;
        unchecked { _nextTokenId++; }
        _safeMint(to, tokenId);
    }

    /// @notice Burn `tokenId`. Caller must be the owner or approved operator.
    ///         Clears any per-token royalty override via ERC721Royalty._burn.
    function burn(uint256 tokenId) external {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "MetaverseItem: caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    // ─── URI management ───────────────────────────────────────────────────────

    /// @notice Update the IPFS base URI. Can be updated until locked. Admin may
    ///         permanently freeze it by calling `lockBaseURI()`.
    function setBaseURI(string memory baseURI) external onlyRole(ADMIN_ROLE) {
        if (_baseURILocked) revert BaseURILocked();
        _baseTokenURI = baseURI;
    }

    /// @notice Permanently lock the base URI so it can never be changed again.
    function lockBaseURI() external onlyRole(ADMIN_ROLE) {
        _baseURILocked = true;
    }

    /// @dev Returns the raw base URI used by `tokenURI`.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Returns `{baseURI}{tokenId}.json` for a minted token.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId); // OZ 4.x – reverts with "ERC721: invalid token ID"
        return string(abi.encodePacked(_baseURI(), tokenId.toString(), ".json"));
    }

    // ─── Overrides required by Solidity ──────────────────────────────────────

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721Royalty) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721Royalty, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}