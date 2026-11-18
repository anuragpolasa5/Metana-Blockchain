// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ═══════════════════════════════════════════════════════════════════
//  SimpleNFT  –  minimal ERC-721 for testing SimpleEnglishAuction
//  No imports needed — paste directly into Remix
//
//  Supports safeTransferFrom() so the seller can escrow the NFT into
//  SimpleEnglishAuction via the onERC721Received() callback pattern.
// ═══════════════════════════════════════════════════════════════════

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract SimpleNFT {

    // ── ERC-721 storage ──────────────────────────────────────────
    string  public name   = "SimpleNFT";
    string  public symbol = "SNFT";

    // tokenId → owner
    mapping(uint256 => address) private _owners;
    // tokenId → approved address
    mapping(uint256 => address) private _tokenApprovals;
    // owner  → operator → approved
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private _nextTokenId = 1;

    // ── Events (ERC-721 required) ────────────────────────────────
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ── Mint ─────────────────────────────────────────────────────
    /**
     * @notice Mint a new token to `to`.
     *         Anyone can mint for testing purposes.
     *         Returns the new tokenId.
     */
    function mint(address to) external returns (uint256) {
        require(to != address(0), "NFT: mint to zero address");
        uint256 tokenId = _nextTokenId++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    // ── ERC-721 core ─────────────────────────────────────────────
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFT: token does not exist");
        return owner;
    }

    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender),
                "NFT: not owner nor approved-for-all");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "NFT: token does not exist");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "NFT: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner ||
            msg.sender == getApproved(tokenId) ||
            isApprovedForAll(owner, msg.sender),
            "NFT: not authorised"
        );
        require(from == owner, "NFT: from != owner");
        require(to != address(0), "NFT: transfer to zero address");

        // Clear approval
        delete _tokenApprovals[tokenId];

        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    /**
     * @notice Safe transfer — calls onERC721Received on the recipient if it is a contract.
     *         Use this to escrow the NFT into SimpleEnglishAuction:
     *           nft.safeTransferFrom(seller, auctionAddress, tokenId)
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(msg.sender, from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(msg.sender, from, to, tokenId, data);
    }

    function _checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(operator, from, tokenId, data)
                returns (bytes4 retval)
            {
                require(
                    retval == IERC721Receiver.onERC721Received.selector,
                    "NFT: transfer to non ERC721Receiver"
                );
            } catch {
                revert("NFT: transfer to non ERC721Receiver");
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x01ffc9a7;   // ERC-165
    }
}
