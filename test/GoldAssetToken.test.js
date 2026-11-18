const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("GoldAssetToken", function () {
  let goldToken, mockXauUsdFeed, mockEthUsdFeed;
  let owner, user1, user2;

  const FEED_SCALE = 10n ** 10n;
  const TOKEN_SCALE = 10n ** 18n;
  const INITIAL_XAU_USD_PRICE = 195000000000n; // $1,950, 8 decimals
  const ETH_USD_PRICE = 250000000000n; // $2,500, 8 decimals
  const MINT_THRESHOLD = ethers.parseEther("2500");
  const UPDATE_INTERVAL = 300;
  const XAU_MAX_STALENESS = 3600;
  const ETH_USD_MAX_STALENESS = 7200;

  const normalize = (rawPrice) => rawPrice * FEED_SCALE;

  const calculateMintCost = (
    amount,
    xauUsdPrice = INITIAL_XAU_USD_PRICE,
    ethUsdPrice = ETH_USD_PRICE
  ) => {
    const usdValue = (normalize(xauUsdPrice) * amount) / TOKEN_SCALE;
    const ethUsdNormalized = normalize(ethUsdPrice);
    return (usdValue * TOKEN_SCALE + ethUsdNormalized - 1n) / ethUsdNormalized;
  };

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    mockXauUsdFeed = await MockV3Aggregator.deploy(8, INITIAL_XAU_USD_PRICE);
    await mockXauUsdFeed.waitForDeployment();

    mockEthUsdFeed = await MockV3Aggregator.deploy(8, ETH_USD_PRICE);
    await mockEthUsdFeed.waitForDeployment();

    const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
    goldToken = await GoldAssetToken.deploy(
      await mockXauUsdFeed.getAddress(),
      await mockEthUsdFeed.getAddress(),
      MINT_THRESHOLD,
      UPDATE_INTERVAL,
      XAU_MAX_STALENESS,
      ETH_USD_MAX_STALENESS
    );
    await goldToken.waitForDeployment();
  });

  describe("Deployment", function () {
    it("should set the correct token name and symbol", async function () {
      expect(await goldToken.name()).to.equal("Gold Asset Token");
      expect(await goldToken.symbol()).to.equal("GXAU");
    });

    it("should set the XAU/USD price feed address", async function () {
      expect(await goldToken.xauUsdFeed()).to.equal(await mockXauUsdFeed.getAddress());
    });

    it("should set the correct mint threshold", async function () {
      expect(await goldToken.mintPriceThreshold()).to.equal(MINT_THRESHOLD);
    });

    it("should set the correct update interval", async function () {
      expect(await goldToken.updateInterval()).to.equal(UPDATE_INTERVAL);
    });

    it("should set independent feed staleness limits", async function () {
      expect(await goldToken.xauMaxStaleness()).to.equal(XAU_MAX_STALENESS);
      expect(await goldToken.ethUsdMaxStaleness()).to.equal(ETH_USD_MAX_STALENESS);
    });

    it("should revert on zero XAU/USD feed in constructor", async function () {
      const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
      await expect(
        GoldAssetToken.deploy(
          ethers.ZeroAddress,
          await mockEthUsdFeed.getAddress(),
          MINT_THRESHOLD,
          UPDATE_INTERVAL,
          XAU_MAX_STALENESS,
          ETH_USD_MAX_STALENESS
        )
      ).to.be.revertedWithCustomError(goldToken, "ZeroAddress");
    });

    it("should revert on zero mintPriceThreshold in constructor", async function () {
      const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
      await expect(
        GoldAssetToken.deploy(
          await mockXauUsdFeed.getAddress(),
          await mockEthUsdFeed.getAddress(),
          0,
          UPDATE_INTERVAL,
          XAU_MAX_STALENESS,
          ETH_USD_MAX_STALENESS
        )
      ).to.be.revertedWithCustomError(goldToken, "InvalidParameter");
    });

    it("should revert on zero updateInterval in constructor", async function () {
      const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
      await expect(
        GoldAssetToken.deploy(
          await mockXauUsdFeed.getAddress(),
          await mockEthUsdFeed.getAddress(),
          MINT_THRESHOLD,
          0,
          XAU_MAX_STALENESS,
          ETH_USD_MAX_STALENESS
        )
      ).to.be.revertedWithCustomError(goldToken, "InvalidParameter");
    });

    it("should revert on XAU staleness below minimum", async function () {
      const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
      await expect(
        GoldAssetToken.deploy(
          await mockXauUsdFeed.getAddress(),
          await mockEthUsdFeed.getAddress(),
          MINT_THRESHOLD,
          UPDATE_INTERVAL,
          30,
          ETH_USD_MAX_STALENESS
        )
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });

    it("should revert on ETH/USD staleness above maximum", async function () {
      const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
      const eightDays = 8 * 24 * 60 * 60;
      await expect(
        GoldAssetToken.deploy(
          await mockXauUsdFeed.getAddress(),
          await mockEthUsdFeed.getAddress(),
          MINT_THRESHOLD,
          UPDATE_INTERVAL,
          XAU_MAX_STALENESS,
          eightDays
        )
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });
  });

  describe("Price Feeds", function () {
    it("should return the current raw XAU/USD price", async function () {
      expect(await goldToken.getLatestPrice()).to.equal(INITIAL_XAU_USD_PRICE);
    });

    it("should return the normalized XAU/USD price for display", async function () {
      const [priceUSD18, feedDecimals] = await goldToken.getAssetPriceUSD();
      expect(priceUSD18).to.equal(normalize(INITIAL_XAU_USD_PRICE));
      expect(feedDecimals).to.equal(8);
    });

    it("should revert on a stale XAU/USD price", async function () {
      await time.increase(XAU_MAX_STALENESS + 1);
      await expect(goldToken.getLatestPrice()).to.be.revertedWithCustomError(
        goldToken,
        "StalePrice"
      );
    });

    it("should revert on a zero XAU/USD price", async function () {
      await mockXauUsdFeed.updateAnswer(0);
      await expect(goldToken.getLatestPrice()).to.be.revertedWithCustomError(
        goldToken,
        "InvalidPrice"
      );
    });

    it("should revert on a negative XAU/USD price", async function () {
      await mockXauUsdFeed.updateAnswer(-100);
      await expect(goldToken.getLatestPrice()).to.be.revertedWithCustomError(
        goldToken,
        "InvalidPrice"
      );
    });

    it("should revert when XAU/USD is outside its sanity band", async function () {
      const outOfBandPrice = 499n * 10n ** 8n;
      await mockXauUsdFeed.updateAnswer(outOfBandPrice);

      await expect(goldToken.getLatestPrice())
        .to.be.revertedWithCustomError(goldToken, "PriceOutOfBand")
        .withArgs(
          await mockXauUsdFeed.getAddress(),
          ethers.parseEther("499"),
          ethers.parseEther("500"),
          ethers.parseEther("20000")
        );
    });

    it("should revert when ETH/USD is outside its sanity band", async function () {
      const outOfBandPrice = 100001n * 10n ** 8n;
      await mockEthUsdFeed.updateAnswer(outOfBandPrice);

      await expect(goldToken.getEthUsdPrice())
        .to.be.revertedWithCustomError(goldToken, "PriceOutOfBand")
        .withArgs(
          await mockEthUsdFeed.getAddress(),
          ethers.parseEther("100001"),
          ethers.parseEther("100"),
          ethers.parseEther("100000")
        );
    });
  });

  describe("Minting", function () {
    it("should allow minting when XAU/USD is below threshold", async function () {
      const mintAmount = ethers.parseEther("1");
      const totalCost = calculateMintCost(mintAmount);

      await goldToken.connect(user1).mint(mintAmount, { value: totalCost });
      expect(await goldToken.balanceOf(user1.address)).to.equal(mintAmount);
      expect(await ethers.provider.getBalance(await goldToken.getAddress())).to.equal(totalCost);
    });

    it("should reject minting when XAU/USD is above threshold", async function () {
      await mockXauUsdFeed.updateAnswer(3000n * 10n ** 8n);

      await expect(
        goldToken.connect(user1).mint(ethers.parseEther("1"), {
          value: ethers.parseEther("10"),
        })
      ).to.be.revertedWithCustomError(goldToken, "PriceAboveThreshold");
    });

    it("should emit TokensMinted with the normalized XAU/USD price", async function () {
      const mintAmount = ethers.parseEther("1");
      const totalCost = calculateMintCost(mintAmount);

      await expect(goldToken.connect(user1).mint(mintAmount, { value: totalCost }))
        .to.emit(goldToken, "TokensMinted")
        .withArgs(user1.address, mintAmount, normalize(INITIAL_XAU_USD_PRICE));
    });

    it("should refund excess ETH via low-level call", async function () {
      const mintAmount = ethers.parseEther("0.001");
      const expectedCost = calculateMintCost(mintAmount);
      const excessValue = expectedCost + ethers.parseEther("1");

      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await goldToken.connect(user1).mint(mintAmount, { value: excessValue });
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(user1.address);

      expect(balanceBefore - balanceAfter - gasCost).to.equal(expectedCost);
    });

    it("should reject minting with insufficient ETH", async function () {
      const mintAmount = ethers.parseEther("1");
      await expect(
        goldToken.connect(user1).mint(mintAmount, { value: 0n })
      ).to.be.revertedWithCustomError(goldToken, "InsufficientPayment");
    });

    it("should handle minting zero amount", async function () {
      await goldToken.connect(user1).mint(0n, { value: 0n });
      expect(await goldToken.balanceOf(user1.address)).to.equal(0n);
    });

    it("should adjust cost when ETH/USD changes", async function () {
      const matchingEthPrice = INITIAL_XAU_USD_PRICE;
      await mockEthUsdFeed.updateAnswer(matchingEthPrice);
      const mintAmount = ethers.parseEther("1");
      const expectedCost = calculateMintCost(
        mintAmount,
        INITIAL_XAU_USD_PRICE,
        matchingEthPrice
      );

      expect(expectedCost).to.equal(ethers.parseEther("1"));
      await goldToken.connect(user1).mint(mintAmount, { value: expectedCost });
      expect(await goldToken.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("should charge exactly 0.78 ETH for one ounce at $1950 with ETH at $2500", async function () {
      const mintAmount = ethers.parseEther("1");
      const expectedCost = calculateMintCost(mintAmount);
      expect(expectedCost).to.equal(ethers.parseEther("0.78"));

      await expect(
        goldToken.connect(user1).mint(mintAmount, { value: expectedCost - 1n })
      )
        .to.be.revertedWithCustomError(goldToken, "InsufficientPayment")
        .withArgs(expectedCost - 1n, expectedCost);

      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await goldToken.connect(user1).mint(mintAmount, { value: expectedCost });
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const balanceAfter = await ethers.provider.getBalance(user1.address);

      expect(balanceBefore - balanceAfter - gasCost).to.equal(expectedCost);
      expect(await goldToken.balanceOf(user1.address)).to.equal(mintAmount);
    });

    it("should scale cost correctly for fractional ounces", async function () {
      const halfOunce = ethers.parseEther("0.5");
      const expectedCost = calculateMintCost(halfOunce);

      expect(expectedCost).to.equal(ethers.parseEther("0.39"));
      await goldToken.connect(user1).mint(halfOunce, { value: expectedCost });
      expect(await goldToken.balanceOf(user1.address)).to.equal(halfOunce);
    });

    it("should prevent dust-cost minting of large token supplies", async function () {
      const largeAmount = ethers.parseEther("1000000");
      expect(calculateMintCost(largeAmount)).to.equal(ethers.parseEther("780000"));
    });
  });

  describe("Price History (Oracle Trigger)", function () {
    it("should record a normalized XAU/USD price on first update", async function () {
      await goldToken.updatePriceHistory();

      expect(await goldToken.getPriceHistoryLength()).to.equal(1);
      const snapshot = await goldToken.priceHistory(0);
      expect(snapshot.price).to.equal(normalize(INITIAL_XAU_USD_PRICE));
    });

    it("should reject update before interval has passed", async function () {
      await goldToken.updatePriceHistory();
      await expect(goldToken.updatePriceHistory()).to.be.revertedWithCustomError(
        goldToken,
        "UpdateTooSoon"
      );
    });

    it("should allow update after interval has passed", async function () {
      await goldToken.updatePriceHistory();
      await time.increase(UPDATE_INTERVAL);
      const nextPrice = 200000000000n;
      await mockXauUsdFeed.updateAnswer(nextPrice);
      await goldToken.updatePriceHistory();

      expect(await goldToken.getPriceHistoryLength()).to.equal(2);
      const snapshot = await goldToken.priceHistory(1);
      expect(snapshot.price).to.equal(normalize(nextPrice));
    });

    it("should return normalized price history ranges", async function () {
      const secondPrice = 200000000000n;
      const thirdPrice = 205000000000n;
      await goldToken.updatePriceHistory();
      await time.increase(UPDATE_INTERVAL);
      await mockXauUsdFeed.updateAnswer(secondPrice);
      await goldToken.updatePriceHistory();
      await time.increase(UPDATE_INTERVAL);
      await mockXauUsdFeed.updateAnswer(thirdPrice);
      await goldToken.updatePriceHistory();

      const history = await goldToken.getPriceHistory(0, 3);
      expect(history.length).to.equal(3);
      expect(history[0].price).to.equal(normalize(INITIAL_XAU_USD_PRICE));
      expect(history[1].price).to.equal(normalize(secondPrice));
      expect(history[2].price).to.equal(normalize(thirdPrice));
    });

    it("checkUpkeep should return true when interval has passed", async function () {
      await goldToken.updatePriceHistory();
      await time.increase(UPDATE_INTERVAL);
      const [upkeepNeeded] = await goldToken.checkUpkeep("0x");
      expect(upkeepNeeded).to.be.true;
    });

    it("checkUpkeep should return false when interval has not passed", async function () {
      await goldToken.updatePriceHistory();
      const [upkeepNeeded] = await goldToken.checkUpkeep("0x");
      expect(upkeepNeeded).to.be.false;
    });

    it("performUpkeep should record the normalized price", async function () {
      await goldToken.performUpkeep("0x");
      expect(await goldToken.getPriceHistoryLength()).to.equal(1);
      expect((await goldToken.priceHistory(0)).price).to.equal(
        normalize(INITIAL_XAU_USD_PRICE)
      );
    });

    it("performUpkeep should return silently when interval has not elapsed", async function () {
      await goldToken.performUpkeep("0x");
      await goldToken.performUpkeep("0x");
      expect(await goldToken.getPriceHistoryLength()).to.equal(1);
    });

    it("performUpkeep should skip silently when XAU/USD is stale", async function () {
      await time.increase(XAU_MAX_STALENESS + 1);
      await goldToken.performUpkeep("0x");
      expect(await goldToken.getPriceHistoryLength()).to.equal(0);
    });
  });

  describe("Admin Functions", function () {
    it("should allow owner to update mint threshold", async function () {
      const newThreshold = ethers.parseEther("3000");
      await goldToken.setMintPriceThreshold(newThreshold);
      expect(await goldToken.mintPriceThreshold()).to.equal(newThreshold);
    });

    it("should allow owner to update interval", async function () {
      await goldToken.setUpdateInterval(600);
      expect(await goldToken.updateInterval()).to.equal(600);
    });

    it("should allow owner to withdraw ETH", async function () {
      const mintAmount = ethers.parseEther("0.001");
      await goldToken.connect(user1).mint(mintAmount, {
        value: calculateMintCost(mintAmount),
      });

      expect(await ethers.provider.getBalance(await goldToken.getAddress())).to.be.gt(0);
      await goldToken.withdraw();
      expect(await ethers.provider.getBalance(await goldToken.getAddress())).to.equal(0);
    });

    it("should reject non-owner from admin functions", async function () {
      await expect(
        goldToken.connect(user1).setMintPriceThreshold(ethers.parseEther("3000"))
      ).to.be.revertedWithCustomError(goldToken, "OwnableUnauthorizedAccount");
      await expect(
        goldToken.connect(user1).setUpdateInterval(100)
      ).to.be.revertedWithCustomError(goldToken, "OwnableUnauthorizedAccount");
      await expect(
        goldToken.connect(user1).withdraw()
      ).to.be.revertedWithCustomError(goldToken, "OwnableUnauthorizedAccount");
    });

    it("should allow owner to update each feed staleness", async function () {
      await goldToken.setXauMaxStaleness(7200);
      await goldToken.setEthUsdMaxStaleness(10800);
      expect(await goldToken.xauMaxStaleness()).to.equal(7200);
      expect(await goldToken.ethUsdMaxStaleness()).to.equal(10800);
    });

    it("should reject XAU staleness below minimum", async function () {
      await expect(
        goldToken.setXauMaxStaleness(30)
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });

    it("should reject ETH/USD staleness above maximum", async function () {
      await expect(
        goldToken.setEthUsdMaxStaleness(8 * 24 * 60 * 60)
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });

    it("should reject a zero per-feed staleness value", async function () {
      await expect(
        goldToken.setXauMaxStaleness(0)
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });

    it("should reject a maximum uint per-feed staleness value", async function () {
      await expect(
        goldToken.setEthUsdMaxStaleness(ethers.MaxUint256)
      ).to.be.revertedWithCustomError(goldToken, "StalenessOutOfBounds");
    });
  });

  describe("setXauUsdFeed Validation", function () {
    it("should revert on zero address", async function () {
      await expect(
        goldToken.setXauUsdFeed(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(goldToken, "ZeroAddress");
    });

    it("should revert if feed reports zero decimals", async function () {
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      const badFeed = await MockV3Aggregator.deploy(0, INITIAL_XAU_USD_PRICE);
      await badFeed.waitForDeployment();
      await expect(
        goldToken.setXauUsdFeed(await badFeed.getAddress())
      ).to.be.revertedWithCustomError(goldToken, "InvalidDecimals");
    });

    it("should emit XauUsdFeedUpdated on valid update", async function () {
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      const newFeed = await MockV3Aggregator.deploy(8, 200000000000n);
      await newFeed.waitForDeployment();

      await expect(goldToken.setXauUsdFeed(await newFeed.getAddress()))
        .to.emit(goldToken, "XauUsdFeedUpdated")
        .withArgs(await mockXauUsdFeed.getAddress(), await newFeed.getAddress());
    });

    it("should accept a valid XAU/USD feed", async function () {
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      const newFeed = await MockV3Aggregator.deploy(8, 200000000000n);
      await newFeed.waitForDeployment();

      await goldToken.setXauUsdFeed(await newFeed.getAddress());
      expect(await goldToken.xauUsdFeed()).to.equal(await newFeed.getAddress());
    });

    it("should reject non-owner from changing XAU/USD feed", async function () {
      await expect(
        goldToken.connect(user1).setXauUsdFeed(await mockXauUsdFeed.getAddress())
      ).to.be.revertedWithCustomError(goldToken, "OwnableUnauthorizedAccount");
    });

    it("changing XAU/USD feed should affect subsequent price queries", async function () {
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      const newFeed = await MockV3Aggregator.deploy(8, 220000000000n);
      await newFeed.waitForDeployment();

      await goldToken.setXauUsdFeed(await newFeed.getAddress());
      expect(await goldToken.getLatestPrice()).to.equal(220000000000n);
    });
  });
});
