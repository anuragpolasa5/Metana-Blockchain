// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title GoldAssetToken
 * @author Anurag
 * @notice Tokenizes real-world gold (XAU) on-chain using Chainlink Price Feeds.
 *         1 token = 1 ounce of gold. Minting is conditional on the current gold price.
 * @dev Uses independent freshness limits and plausible price bands for the XAU/USD and
 *      ETH/USD feeds. All price comparisons and stored snapshots use 18 decimals.
 */
contract GoldAssetToken is ERC20, Ownable {
    uint256 public constant MIN_STALENESS = 60;
    uint256 public constant MAX_STALENESS_BOUND = 7 days;
    uint8 private constant TARGET_DECIMALS = 18;

    // Conservative sanity bands in 18-decimal USD units.
    uint256 public constant MIN_XAU_PRICE = 500e18;
    uint256 public constant MAX_XAU_PRICE = 20_000e18;
    uint256 public constant MIN_ETH_USD_PRICE = 100e18;
    uint256 public constant MAX_ETH_USD_PRICE = 100_000e18;

    // RWA-02: Fetches the XAU-to-USD price using a Chainlink oracle.
    AggregatorV3Interface public xauUsdFeed;
    AggregatorV3Interface public ethUsdFeed;

    /// @notice Maximum gold price (18-decimal USD) at which minting is allowed.
    uint256 public mintPriceThreshold;

    struct PriceSnapshot {
        uint256 price;
        uint256 timestamp;
    }

    enum FeedStatus {
        Ok,
        InvalidRound,
        Stale,
        InvalidPrice,
        OutOfBand
    }

    // RWA-05: priceHistory tracks normalized XAU/USD values over time.
    PriceSnapshot[] public priceHistory;
    uint256 public updateInterval;
    uint256 public lastUpdateTimestamp;

    /// @notice Maximum acceptable age for the XAU/USD feed response.
    uint256 public xauMaxStaleness;

    /// @notice Maximum acceptable age for the ETH/USD feed response.
    uint256 public ethUsdMaxStaleness;

    event TokensMinted(address indexed to, uint256 amount, uint256 normalizedPriceAtMint);
    event PriceUpdated(uint256 normalizedPrice, uint256 timestamp);
    event MintThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event UpdateIntervalChanged(uint256 oldInterval, uint256 newInterval);
    event XauUsdFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event EthUsdFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event FeedStalenessUpdated(address indexed feed, uint256 oldStaleness, uint256 newStaleness);

    error PriceAboveThreshold(uint256 normalizedPrice, uint256 threshold);
    error PriceOutOfBand(address feed, uint256 normalizedPrice, uint256 minPrice, uint256 maxPrice);
    error StalePrice();
    error UpdateTooSoon(uint256 nextAllowedTime);
    error InvalidPrice();
    error ZeroAddress();
    error InvalidDecimals(uint8 feedDecimals);
    error EthTransferFailed();
    error InvalidRoundData();
    error StalenessOutOfBounds(uint256 value, uint256 min, uint256 max);
    error InvalidParameter(string param);
    error FeedValidationFailed(address feed);
    error InsufficientPayment(uint256 sent, uint256 required);

    /**
     * @notice Deploys the token with independent XAU/USD and ETH/USD oracle settings.
     * @param _xauUsdFeed Chainlink XAU-to-USD price feed.
     * @param _ethUsdFeed Chainlink ETH-to-USD price feed.
     * @param _mintPriceThreshold Maximum minting price in 18-decimal USD.
     * @param _updateInterval Seconds between price-history updates.
     * @param _xauMaxStaleness Maximum acceptable XAU/USD response age.
     * @param _ethUsdMaxStaleness Maximum acceptable ETH/USD response age.
     */
    constructor(
        address _xauUsdFeed,
        address _ethUsdFeed,
        uint256 _mintPriceThreshold,
        uint256 _updateInterval,
        uint256 _xauMaxStaleness,
        uint256 _ethUsdMaxStaleness
    ) ERC20("Gold Asset Token", "GXAU") Ownable(msg.sender) {
        // RWA-01: ERC20 structure where 1 token represents 1 ounce of gold.
        if (_xauUsdFeed == address(0) || _ethUsdFeed == address(0)) revert ZeroAddress();
        if (_mintPriceThreshold == 0) revert InvalidParameter("mintPriceThreshold");
        if (_updateInterval == 0) revert InvalidParameter("updateInterval");
        _validateStaleness(_xauMaxStaleness);
        _validateStaleness(_ethUsdMaxStaleness);

        _validateFeed(_xauUsdFeed, MIN_XAU_PRICE, MAX_XAU_PRICE);
        _validateFeed(_ethUsdFeed, MIN_ETH_USD_PRICE, MAX_ETH_USD_PRICE);

        xauUsdFeed = AggregatorV3Interface(_xauUsdFeed);
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        mintPriceThreshold = _mintPriceThreshold;
        updateInterval = _updateInterval;
        xauMaxStaleness = _xauMaxStaleness;
        ethUsdMaxStaleness = _ethUsdMaxStaleness;
    }

    function _validateStaleness(uint256 value) internal pure {
        if (value < MIN_STALENESS || value > MAX_STALENESS_BOUND) {
            revert StalenessOutOfBounds(value, MIN_STALENESS, MAX_STALENESS_BOUND);
        }
    }

    /**
     * @dev Validates feed decimals, basic liveness, and its current price band. Runtime
     *      reads additionally enforce round completeness and the feed-specific freshness limit.
     */
    function _validateFeed(address feedAddress, uint256 minPrice, uint256 maxPrice) internal view {
        AggregatorV3Interface feed = AggregatorV3Interface(feedAddress);
        uint8 feedDecimals = feed.decimals();
        if (feedDecimals == 0 || feedDecimals > TARGET_DECIMALS) {
            revert InvalidDecimals(feedDecimals);
        }

        (uint80 roundId, int256 answer,,,) = feed.latestRoundData();
        if (roundId == 0 || answer <= 0) revert FeedValidationFailed(feedAddress);

        (bool normalized, uint256 priceNorm) = _tryNormalize(answer, feedDecimals);
        if (!normalized || priceNorm < minPrice || priceNorm > maxPrice) {
            revert PriceOutOfBand(
                feedAddress,
                normalized ? priceNorm : type(uint256).max,
                minPrice,
                maxPrice
            );
        }
    }

    function _tryNormalize(int256 rawPrice, uint8 feedDecimals)
        internal
        pure
        returns (bool ok, uint256 normalizedPrice)
    {
        if (rawPrice <= 0 || feedDecimals == 0 || feedDecimals > TARGET_DECIMALS) return (false, 0);
        uint256 scale = 10 ** (TARGET_DECIMALS - feedDecimals);
        uint256 unsignedPrice = uint256(rawPrice);
        if (unsignedPrice > type(uint256).max / scale) return (false, 0);
        return (true, unsignedPrice * scale);
    }

    /**
     * @dev Reads and validates one oracle round without reverting, allowing Automation to
     *      skip unhealthy rounds. Returns both the feed-native and normalized prices so
     *      callers never repeat decimal conversion.
     */
    function _tryGetFeedPrice(
        AggregatorV3Interface feed,
        uint256 maxStaleness,
        uint256 minPrice,
        uint256 maxPrice
    ) internal view returns (FeedStatus status, int256 rawPrice, uint256 normalizedPrice) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        if (roundId == 0 || answeredInRound < roundId) {
            return (FeedStatus.InvalidRound, answer, 0);
        }
        if (updatedAt > block.timestamp || block.timestamp - updatedAt > maxStaleness) {
            return (FeedStatus.Stale, answer, 0);
        }
        if (answer <= 0) return (FeedStatus.InvalidPrice, answer, 0);

        (bool normalized, uint256 priceNorm) = _tryNormalize(answer, feed.decimals());
        if (!normalized) return (FeedStatus.InvalidPrice, answer, 0);
        if (priceNorm < minPrice || priceNorm > maxPrice) {
            return (FeedStatus.OutOfBand, answer, priceNorm);
        }
        return (FeedStatus.Ok, answer, priceNorm);
    }

    function _getFeedPrice(
        AggregatorV3Interface feed,
        uint256 maxStaleness,
        uint256 minPrice,
        uint256 maxPrice
    ) internal view returns (int256 rawPrice, uint256 normalizedPrice) {
        (FeedStatus status, int256 answer, uint256 priceNorm) =
            _tryGetFeedPrice(feed, maxStaleness, minPrice, maxPrice);

        if (status == FeedStatus.Ok) return (answer, priceNorm);
        if (status == FeedStatus.InvalidRound) revert InvalidRoundData();
        if (status == FeedStatus.Stale) revert StalePrice();
        if (status == FeedStatus.OutOfBand) {
            revert PriceOutOfBand(address(feed), priceNorm, minPrice, maxPrice);
        }
        revert InvalidPrice();
    }

    // RWA-02: Fetches the current XAU/USD price in feed-native decimals.
    function getLatestPrice() public view returns (int256 rawPrice) {
        (rawPrice,) = _getFeedPrice(
            xauUsdFeed,
            xauMaxStaleness,
            MIN_XAU_PRICE,
            MAX_XAU_PRICE
        );
    }

    /// @notice Fetches the current ETH/USD price in feed-native decimals.
    function getEthUsdPrice() public view returns (int256 rawPrice) {
        (rawPrice,) = _getFeedPrice(
            ethUsdFeed,
            ethUsdMaxStaleness,
            MIN_ETH_USD_PRICE,
            MAX_ETH_USD_PRICE
        );
    }

    // RWA-03: Displays the current gold price in normalized USD.
    function getAssetPriceUSD() external view returns (uint256 priceUSD18, uint8 feedDecimals) {
        (, priceUSD18) = _getFeedPrice(
            xauUsdFeed,
            xauMaxStaleness,
            MIN_XAU_PRICE,
            MAX_XAU_PRICE
        );
        feedDecimals = xauUsdFeed.decimals();
    }

    // RWA-04: Conditional minting with a dynamic oracle-derived ETH cost.
    function mint(uint256 amount) external payable {
        (, uint256 xauPriceNorm) = _getFeedPrice(
            xauUsdFeed,
            xauMaxStaleness,
            MIN_XAU_PRICE,
            MAX_XAU_PRICE
        );

        // RWA-04a: Mint only while the normalized XAU price is at or below the threshold.
        if (xauPriceNorm > mintPriceThreshold) {
            revert PriceAboveThreshold(xauPriceNorm, mintPriceThreshold);
        }

        // RWA-04b: Convert the XAU-denominated USD value to ETH using ETH/USD.
        uint256 usdValue = (xauPriceNorm * amount) / 1e18;
        (, uint256 ethUsdPriceNorm) = _getFeedPrice(
            ethUsdFeed,
            ethUsdMaxStaleness,
            MIN_ETH_USD_PRICE,
            MAX_ETH_USD_PRICE
        );
        uint256 totalCost = (usdValue * 1e18 + ethUsdPriceNorm - 1) / ethUsdPriceNorm;

        if (msg.value < totalCost) revert InsufficientPayment(msg.value, totalCost);

        _mint(msg.sender, amount);
        emit TokensMinted(msg.sender, amount, xauPriceNorm);

        if (msg.value > totalCost) {
            (bool success,) = payable(msg.sender).call{value: msg.value - totalCost}("");
            if (!success) revert EthTransferFailed();
        }
    }

    // RWA-05a: Chainlink Automation eligibility check.
    function checkUpkeep(bytes calldata)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = (block.timestamp - lastUpdateTimestamp) >= updateInterval;
        performData = "";
    }

    // RWA-05b/RWA-05c: Non-reverting scheduled price recording.
    function performUpkeep(bytes calldata) external {
        if ((block.timestamp - lastUpdateTimestamp) < updateInterval) return;

        (FeedStatus status,, uint256 xauPriceNorm) = _tryGetFeedPrice(
            xauUsdFeed,
            xauMaxStaleness,
            MIN_XAU_PRICE,
            MAX_XAU_PRICE
        );
        if (status != FeedStatus.Ok) return;

        priceHistory.push(PriceSnapshot({price: xauPriceNorm, timestamp: block.timestamp}));
        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(xauPriceNorm, block.timestamp);
    }

    // RWA-05d: Permissionless manual price recording with interval enforcement.
    function updatePriceHistory() external {
        if ((block.timestamp - lastUpdateTimestamp) < updateInterval) {
            revert UpdateTooSoon(lastUpdateTimestamp + updateInterval);
        }

        (, uint256 xauPriceNorm) = _getFeedPrice(
            xauUsdFeed,
            xauMaxStaleness,
            MIN_XAU_PRICE,
            MAX_XAU_PRICE
        );
        priceHistory.push(PriceSnapshot({price: xauPriceNorm, timestamp: block.timestamp}));
        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(xauPriceNorm, block.timestamp);
    }

    function getPriceHistoryLength() external view returns (uint256) {
        return priceHistory.length;
    }

    function getPriceHistory(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (PriceSnapshot[] memory)
    {
        require(endIndex <= priceHistory.length, "End index out of bounds");
        require(startIndex < endIndex, "Invalid range");
        PriceSnapshot[] memory history = new PriceSnapshot[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            history[i - startIndex] = priceHistory[i];
        }
        return history;
    }

    function setMintPriceThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert InvalidParameter("mintPriceThreshold");
        uint256 oldThreshold = mintPriceThreshold;
        mintPriceThreshold = newThreshold;
        emit MintThresholdUpdated(oldThreshold, newThreshold);
    }

    function setUpdateInterval(uint256 newInterval) external onlyOwner {
        if (newInterval == 0) revert InvalidParameter("updateInterval");
        uint256 oldInterval = updateInterval;
        updateInterval = newInterval;
        emit UpdateIntervalChanged(oldInterval, newInterval);
    }

    function setXauUsdFeed(address newXauUsdFeed) external onlyOwner {
        if (newXauUsdFeed == address(0)) revert ZeroAddress();
        _validateFeed(newXauUsdFeed, MIN_XAU_PRICE, MAX_XAU_PRICE);
        address oldFeed = address(xauUsdFeed);
        xauUsdFeed = AggregatorV3Interface(newXauUsdFeed);
        emit XauUsdFeedUpdated(oldFeed, newXauUsdFeed);
    }

    function setEthUsdFeed(address newEthUsdFeed) external onlyOwner {
        if (newEthUsdFeed == address(0)) revert ZeroAddress();
        _validateFeed(newEthUsdFeed, MIN_ETH_USD_PRICE, MAX_ETH_USD_PRICE);
        address oldFeed = address(ethUsdFeed);
        ethUsdFeed = AggregatorV3Interface(newEthUsdFeed);
        emit EthUsdFeedUpdated(oldFeed, newEthUsdFeed);
    }

    function setXauMaxStaleness(uint256 newMaxStaleness) external onlyOwner {
        _validateStaleness(newMaxStaleness);
        uint256 oldStaleness = xauMaxStaleness;
        xauMaxStaleness = newMaxStaleness;
        emit FeedStalenessUpdated(address(xauUsdFeed), oldStaleness, newMaxStaleness);
    }

    function setEthUsdMaxStaleness(uint256 newMaxStaleness) external onlyOwner {
        _validateStaleness(newMaxStaleness);
        uint256 oldStaleness = ethUsdMaxStaleness;
        ethUsdMaxStaleness = newMaxStaleness;
        emit FeedStalenessUpdated(address(ethUsdFeed), oldStaleness, newMaxStaleness);
    }

    function withdraw() external onlyOwner {
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        if (!success) revert EthTransferFailed();
    }
}
