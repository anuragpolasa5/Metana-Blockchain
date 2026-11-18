// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ═══════════════════════════════════════════════════════════════════
//  Minimal ERC-721 interface
//  transferFrom     – used to return the NFT to the seller on cancel,
//                     and to transfer it to the winner on settlement.
//  safeTransferFrom – used by the seller to escrow the NFT into this
//                     contract; triggers onERC721Received() which
//                     starts the auction without a separate approve tx.
//  ownerOf          – used in claimWinnerRefund() to detect whether
//                     the NFT is still held in escrow.
// ═══════════════════════════════════════════════════════════════════
interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

// ═══════════════════════════════════════════════════════════════════
//  IERC721Receiver  (EIP-721 §safeTransfer callback)
// ═══════════════════════════════════════════════════════════════════
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// ═══════════════════════════════════════════════════════════════════
//  Inline ReentrancyGuard  (AU-9 – no npm needed)
// ═══════════════════════════════════════════════════════════════════
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ═══════════════════════════════════════════════════════════════════
//  SimpleEnglishAuction
// ═══════════════════════════════════════════════════════════════════
//
//  ┌─ REMIX DEPLOYMENT CHECKLIST ──────────────────────────────────┐
//  │ 1. Compiler  : 0.8.20  │  EVM : paris  │  Optimiser : ON     │
//  │ 2. CONTRACT dropdown   →  SimpleEnglishAuction                │
//  │ 3. Constructor arguments (deploy the auction first):          │
//  │      _nftContract   : 0x... (ERC-721 address)                 │
//  │      _tokenId       : 1                                       │
//  │      _startPrice    : 1000000000000000000  (1 ETH in wei)     │
//  │      _biddingPeriod : 300  (5 minutes in seconds)             │
//  │ 4. After deploying, the seller escrows the NFT by calling     │
//  │    nftContract.safeTransferFrom(seller, auctionAddr, tokenId) │
//  │    This triggers onERC721Received() and STARTS the auction — │
//  │    no separate approve() transaction is needed.               │
//  └───────────────────────────────────────────────────────────────┘
//
//  ┌─ TEST FLOW ────────────────────────────────────────────────────┐
//  │ 1. Deploy auction with constructor args above.                 │
//  │ 2. Seller calls nftContract.safeTransferFrom(...)              │
//  │    → NFT escrowed, AuctionStarted event emitted.              │
//  │ 3. Bidder A → bid()  VALUE = 1 ETH   (first bid)              │
//  │    Bidder B → bid()  VALUE = 1.1 ETH (must be ≥ 10% higher)  │
//  │    Bidder A → claimRefund()  (pulls outbid ETH back)          │
//  │ 4. After _biddingPeriod seconds from auction start:           │
//  │      anyone → end()  (pays seller, transfers escrowed NFT)    │
//  │                                                               │
//  │ CANCEL PATH (no bids only):                                   │
//  │   Seller → cancel()  → escrowed NFT returned to seller        │
//  └───────────────────────────────────────────────────────────────┘

contract SimpleEnglishAuction is ReentrancyGuard, IERC721Receiver {

    // ── Custom errors (AU-7) ─────────────────────────────────────
    error AuctionNotActive();
    error AuctionAlreadyEnded();
    error AuctionAlreadyCancelled();
    error AuctionNotEnded();
    error AuctionNotStarted();
    error BidTooLow(uint256 required, uint256 provided);
    error NoBidsPlaced();
    error BidsAlreadyPlaced();
    error NotSeller();
    error NothingToRefund();
    error NotHighestBidder();
    error ETHTransferFailed();
    error WrongNFT();
    error AlreadyEscrowed();

    // ── State enum (AU-2) ────────────────────────────────────────
    // NONE     = auction deployed but NFT not yet escrowed
    // STARTED  = NFT received via safeTransferFrom; bidding is live
    // ENDED    = auction settled via end()
    // CANCELLED = auction cancelled via cancel() or claimWinnerRefund()
    enum AuctionState { NONE, STARTED, ENDED, CANCELLED }

    // ── Immutables set at construction (AU-1) ────────────────────
    IERC721 public immutable nftContract;
    uint256 public immutable tokenId;
    uint256 public immutable startPrice;   // minimum first bid (wei)
    uint256 public immutable biddingPeriod; // duration in seconds
    address public immutable seller;

    uint256 public endTime;                // set when NFT is received (mutable for anti-sniping)

    uint256 public constant MAX_BIDDING_PERIOD  = 30 days;
    uint256 public constant TIME_EXTENSION      = 120; // anti-sniping extension in seconds
    /// @notice Grace period after endTime before the winner refund escape-hatch opens.
    ///         Prevents the winner from front-running a normal end() call.
    uint256 public constant WINNER_REFUND_DELAY = 1 days;

    // ── Mutable auction state ────────────────────────────────────
    AuctionState public state; // starts as AuctionState.NONE (default 0)

    address public highestBidder;
    uint256 public highestBid;

    /// AU-4: out-bidder → refundable ETH
    mapping(address => uint256) public refunds;

    // ── Events ───────────────────────────────────────────────────
    event NewBid(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 price);   // AU-5
    event AuctionStarted(address indexed seller, uint256 tokenId, uint256 endTime);
    event AuctionCancelledEvent();
    event RefundClaimed(address indexed bidder, uint256 amount);
    /// @notice Emitted by claimWinnerRefund() – ETH is queued, not yet sent.
    ///         Distinct from RefundClaimed (which fires when ETH is actually transferred).
    event WinnerRefundQueued(address indexed winner, uint256 amount);

    // ── Constructor (AU-1) ───────────────────────────────────────
    /**
     * @param _nftContract   ERC-721 contract address of the token being auctioned.
     * @param _tokenId       Token ID up for auction.
     * @param _startPrice    Minimum first bid in wei (e.g. 1000000000000000000 = 1 ETH).
     * @param _biddingPeriod Duration of auction in seconds (e.g. 300 = 5 minutes).
     *
     * NOTE: The constructor only records parameters. The auction STARTS when the seller
     * calls nftContract.safeTransferFrom(seller, address(this), tokenId), which triggers
     * onERC721Received() and begins the bidding window. This design:
     *   - eliminates the separate approve() transaction
     *   - uses the ERC-721 safe-transfer callback as the authoritative start signal
     *   - sets state = STARTED atomically when the NFT is escrowed
     */
    constructor(
        address _nftContract,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _biddingPeriod
    ) {
        require(_nftContract  != address(0), "SEA: zero NFT address");
        require(_startPrice   >  0,          "SEA: startPrice must be > 0");
        require(_biddingPeriod > 0,          "SEA: biddingPeriod must be > 0");
        require(_biddingPeriod <= MAX_BIDDING_PERIOD, "SEA: biddingPeriod too long");

        nftContract   = IERC721(_nftContract);
        tokenId       = _tokenId;
        startPrice    = _startPrice;
        biddingPeriod = _biddingPeriod;
        seller        = msg.sender;
        // state remains AuctionState.NONE until the NFT is received
    }

    // ── ERC-721 Receiver callback – auction start ────────────────
    /**
     * @notice Called by the NFT contract when the seller transfers the token
     *         to this auction contract via safeTransferFrom().
     *
     *         This is the recommended way to start the auction:
     *           nftContract.safeTransferFrom(seller, address(this), tokenId)
     *
     *         Checks performed:
     *           - Only the configured nftContract may call this
     *           - Only the seller may initiate the transfer
     *           - Only the configured tokenId is accepted
     *           - The auction must still be in NONE state (not yet started)
     *
     *         On success: sets state = STARTED, records endTime, emits AuctionStarted.
     *
     * @return bytes4  ERC-721 magic value (IERC721Receiver.onERC721Received.selector)
     */
    function onERC721Received(
        address /* operator */,
        address from,
        uint256 _tokenId,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        // Only accept from the configured NFT contract
        if (msg.sender != address(nftContract)) revert WrongNFT();
        // Only the seller may escrow the NFT
        if (from != seller)                     revert NotSeller();
        // Only the configured tokenId is accepted
        if (_tokenId != tokenId)                revert WrongNFT();
        // Prevent double-escrow
        if (state != AuctionState.NONE)         revert AlreadyEscrowed();

        // Start the auction
        state   = AuctionState.STARTED;
        endTime = block.timestamp + biddingPeriod;

        emit AuctionStarted(seller, tokenId, endTime);

        return IERC721Receiver.onERC721Received.selector;
    }

    // ── AU-3  Place a bid ────────────────────────────────────────
    /**
     * @notice Place a bid.
     *         First bid must be >= startPrice.
     *         Every subsequent bid must exceed the current highest by >= 10 %.
     *
     *  Minimum next bid = ceil(highestBid * 1.1)
     *  Computed using ceiling division: (highestBid * 11 + 9) / 10
     *
     *  In Remix: enter the wei amount in the VALUE field, then click bid().
     */
    function bid() external payable nonReentrant {
        if (state == AuctionState.NONE)        revert AuctionNotStarted();
        if (msg.sender == seller)              revert NotSeller();
        if (state == AuctionState.ENDED)       revert AuctionAlreadyEnded();
        if (state == AuctionState.CANCELLED)   revert AuctionAlreadyCancelled();
        if (block.timestamp >= endTime)        revert AuctionAlreadyEnded();

        // Compute minimum acceptable bid with ceiling division for exact 10% increase
        uint256 minBid = (highestBid == 0)
            ? startPrice
            : (highestBid * 11 + 9) / 10;

        if (msg.value < minBid) revert BidTooLow(minBid, msg.value);

        // Queue previous leader's ETH for refund (AU-4)
        if (highestBidder != address(0)) {
            refunds[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid    = msg.value;

        // Anti-sniping: extend auction if bid placed in final TIME_EXTENSION seconds
        if (endTime - block.timestamp < TIME_EXTENSION) {
            endTime = block.timestamp + TIME_EXTENSION;
        }

        emit NewBid(msg.sender, msg.value);
    }

    // ── AU-5  End the auction ────────────────────────────────────
    /**
     * @notice Settle the auction after the bidding period.
     *         Pays the seller and transfers the escrowed NFT to the winner.
     *         Anyone may call this once endTime has passed.
     */
    function end() external nonReentrant {
        if (state == AuctionState.NONE)      revert AuctionNotStarted();
        if (state == AuctionState.ENDED)     revert AuctionAlreadyEnded();
        if (state == AuctionState.CANCELLED) revert AuctionAlreadyCancelled();
        if (block.timestamp < endTime)       revert AuctionNotEnded();
        if (highestBidder == address(0))     revert NoBidsPlaced();

        state = AuctionState.ENDED;

        address winner = highestBidder;
        uint256 price  = highestBid;

        // Queue seller payment via pull pattern to avoid DoS from a non-payable
        // recipient contract or a reverting fallback.
        refunds[seller] += price;

        emit AuctionEnded(winner, price);

        // Transfer escrowed NFT from this contract to the winner.
        nftContract.transferFrom(address(this), winner, tokenId);
    }

    // ── AU-6  Seller cancel (no-bids only) ───────────────────────
    /**
     * @notice Seller cancels before any bids have been placed.
     *         Returns the escrowed NFT to the seller on cancellation.
     *         Can only be called once the auction has started (NFT is in escrow).
     */
    function cancel() external nonReentrant {
        if (msg.sender != seller)            revert NotSeller();
        if (state == AuctionState.NONE)      revert AuctionNotStarted();
        if (state == AuctionState.ENDED)     revert AuctionAlreadyEnded();
        if (state == AuctionState.CANCELLED) revert AuctionAlreadyCancelled();
        if (highestBidder != address(0))     revert BidsAlreadyPlaced();

        state = AuctionState.CANCELLED;
        emit AuctionCancelledEvent();

        // Return the escrowed NFT to the seller.
        nftContract.transferFrom(address(this), seller, tokenId);
    }

    // ── AU-4  Refund pull pattern ────────────────────────────────
    /**
     * @notice Out-bidders withdraw their ETH at any time.
     *         Pull pattern protects against reentrancy (AU-9).
     */
    function claimRefund() external nonReentrant {
        uint256 amount = refunds[msg.sender];
        if (amount == 0) revert NothingToRefund();

        refunds[msg.sender] = 0; // CEI: zero before external call

        emit RefundClaimed(msg.sender, amount);

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert ETHTransferFailed();
    }

    // ── FIX: Winner escape hatch (restricted to failed settlement) ──────────
    /**
     * @notice Emergency withdrawal for the highest bidder ONLY if normal settlement
     *         is impossible — i.e., the NFT is no longer in this contract's escrow.
     *
     *         Conditions to qualify:
     *           • Auction is in STARTED state (end() not yet called)
     *           • Bidding period has elapsed PLUS WINNER_REFUND_DELAY grace period
     *           • Caller is the current highest bidder
     *           • The NFT is NOT currently owned by this contract (settlement failed)
     *
     *         This ensures the winner cannot voluntarily escape a binding auction result
     *         — they can only claim a refund when normal settlement truly has failed.
     *
     *         If the NFT is still in escrow, end() should be called instead.
     */
    function claimWinnerRefund() external nonReentrant {
        if (state != AuctionState.STARTED)                        revert AuctionNotActive();
        // Require WINNER_REFUND_DELAY to have elapsed so the winner cannot
        // front-run an honest end() call immediately after endTime.
        if (block.timestamp < endTime + WINNER_REFUND_DELAY)      revert AuctionNotEnded();
        // Use dedicated error rather than the misleading NothingToRefund.
        if (msg.sender != highestBidder)                          revert NotHighestBidder();

        // Only allow refund if the NFT is NOT in escrow.
        // This prevents the winner from voluntarily unwinding a valid auction result.
        // If the NFT is still here, end() should be called to settle normally.
        try nftContract.ownerOf(tokenId) returns (address currentOwner) {
            // Token still exists and is owned by this contract — settlement is possible
            if (currentOwner == address(this)) {
                revert AuctionNotEnded(); // Normal end() path should be used
            }
            // Token exists but is owned elsewhere — NFT left escrow outside normal flow.
            // Proceed with refund (seller takes the loss).
        } catch {
            // ownerOf reverted (token burned or contract is non-standard).
            // Proceed with refund (seller takes the loss).
        }

        uint256 amount = highestBid;

        // Mark settled so this path can only be taken once
        state         = AuctionState.CANCELLED;
        highestBid    = 0;
        highestBidder = address(0);

        // Emit WinnerRefundQueued (not RefundClaimed) because only the refunds mapping
        // is credited here; the actual ETH transfer happens in claimRefund(), which
        // emits RefundClaimed.
        refunds[msg.sender] += amount;
        emit WinnerRefundQueued(msg.sender, amount);
    }

    // ── View helpers ─────────────────────────────────────────────

    /// @notice Minimum wei required to become the new highest bidder.
    function minimumNextBid() external view returns (uint256) {
        if (highestBid == 0) return startPrice;
        return (highestBid * 11 + 9) / 10;
    }

    /// @notice Seconds left before the auction closes (0 if already past or not started).
    function timeRemaining() external view returns (uint256) {
        if (state == AuctionState.NONE)    return 0;
        if (block.timestamp >= endTime)    return 0;
        return endTime - block.timestamp;
    }

    /// @notice Current block timestamp — useful for computing deadlines in Remix.
    function currentTime() external view returns (uint256) {
        return block.timestamp;
    }

    // ── Fallbacks ────────────────────────────────────────────────
    receive()  external payable { revert("SEA: use bid()"); }
    fallback() external payable { revert("SEA: use bid()"); }
}
