const { ethers, network } = require("hardhat");

const BPS = 10_000n;
const DEFAULT_THRESHOLD_BPS = 11_000n; // 110% of the live XAU/USD price
const MIN_STALENESS = 60;
const MAX_STALENESS = 7 * 24 * 60 * 60;

// Heartbeats are specific to these Ethereum Sepolia feeds. Deployment requires a
// staleness window of at least 2x each heartbeat.
// XAU/USD: https://data.chain.link/feeds/ethereum-testnet/sepolia/xau-usd
// ETH/USD: https://data.chain.link/feeds/ethereum-testnet/sepolia/eth-usd
const SEPOLIA_XAU_HEARTBEAT = 24 * 60 * 60;
const SEPOLIA_ETH_USD_HEARTBEAT = 60 * 60;

const AGGREGATOR_ABI = [
  "function decimals() view returns (uint8)",
  "function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)",
];

function readPositiveInteger(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  if (!/^\d+$/.test(raw) || Number(raw) <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return Number(raw);
}

function validateStaleness(name, value, heartbeat) {
  const minimumForFeed = heartbeat * 2;
  if (value < minimumForFeed) {
    throw new Error(`${name} must be at least 2x the feed heartbeat (${minimumForFeed} seconds)`);
  }
  if (value < MIN_STALENESS || value > MAX_STALENESS) {
    throw new Error(`${name} must be between ${MIN_STALENESS} and ${MAX_STALENESS} seconds`);
  }
}

async function readNormalizedPrice(feedAddress, maxStaleness, label) {
  const feed = new ethers.Contract(feedAddress, AGGREGATOR_ABI, ethers.provider);
  const decimals = await feed.decimals();
  const [roundId, answer, , updatedAt, answeredInRound] = await feed.latestRoundData();
  const latestBlock = await ethers.provider.getBlock("latest");
  if (!latestBlock) throw new Error("Unable to read the latest block timestamp");
  const now = BigInt(latestBlock.timestamp);

  if (roundId === 0n || answeredInRound < roundId || answer <= 0n) {
    throw new Error(`${label} returned invalid round data`);
  }
  if (updatedAt > now || now - updatedAt > BigInt(maxStaleness)) {
    throw new Error(`${label} is stale; refusing to deploy`);
  }
  if (decimals === 0n || decimals > 18n) {
    throw new Error(`${label} has unsupported decimals: ${decimals}`);
  }

  return answer * 10n ** (18n - decimals);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  let xauUsdFeedAddress;
  let ethUsdFeedAddress;
  let xauHeartbeat;
  let ethUsdHeartbeat;

  if (network.name === "sepolia") {
    xauUsdFeedAddress = "0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea";
    ethUsdFeedAddress = "0x694AA1769357215DE4FAC081bf1f309aDC325306";
    xauHeartbeat = SEPOLIA_XAU_HEARTBEAT;
    ethUsdHeartbeat = SEPOLIA_ETH_USD_HEARTBEAT;
  } else {
    console.log("Deploying mock feeds for local testing...");
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockXauFeed = await MockV3Aggregator.deploy(8, 195000000000n);
    const mockEthFeed = await MockV3Aggregator.deploy(8, 250000000000n);
    await Promise.all([mockXauFeed.waitForDeployment(), mockEthFeed.waitForDeployment()]);
    xauUsdFeedAddress = await mockXauFeed.getAddress();
    ethUsdFeedAddress = await mockEthFeed.getAddress();
    xauHeartbeat = 30 * 60;
    ethUsdHeartbeat = 30 * 60;
  }

  const xauMaxStaleness = readPositiveInteger("XAU_MAX_STALENESS", xauHeartbeat * 2);
  const ethUsdMaxStaleness = readPositiveInteger("ETH_USD_MAX_STALENESS", ethUsdHeartbeat * 2);
  validateStaleness("XAU_MAX_STALENESS", xauMaxStaleness, xauHeartbeat);
  validateStaleness("ETH_USD_MAX_STALENESS", ethUsdMaxStaleness, ethUsdHeartbeat);

  const currentXauPrice = await readNormalizedPrice(
    xauUsdFeedAddress,
    xauMaxStaleness,
    "XAU/USD feed"
  );
  // An explicit threshold is allowed, but a bad value aborts before broadcasting.
  const mintThreshold = process.env.MINT_THRESHOLD_USD
    ? ethers.parseUnits(process.env.MINT_THRESHOLD_USD, 18)
    : (currentXauPrice * DEFAULT_THRESHOLD_BPS) / BPS;
  if (mintThreshold <= currentXauPrice) {
    throw new Error("MINT_THRESHOLD_USD must be greater than the live XAU/USD price");
  }

  const updateInterval = readPositiveInteger("UPDATE_INTERVAL", 300);
  const GoldAssetToken = await ethers.getContractFactory("GoldAssetToken");
  const goldToken = await GoldAssetToken.deploy(
    xauUsdFeedAddress,
    ethUsdFeedAddress,
    mintThreshold,
    updateInterval,
    xauMaxStaleness,
    ethUsdMaxStaleness
  );
  await goldToken.waitForDeployment();

  console.log("\n═══════════════════════════════════════════════════");
  console.log("  GoldAssetToken:", await goldToken.getAddress());
  console.log("  XAU/USD Feed:", xauUsdFeedAddress);
  console.log("  ETH/USD Feed:", ethUsdFeedAddress);
  console.log("  Live XAU/USD (18dp):", currentXauPrice.toString());
  console.log("  Mint Threshold (18dp):", mintThreshold.toString());
  console.log("  Update Interval:", updateInterval, "seconds");
  console.log("  XAU Max Staleness:", xauMaxStaleness, "seconds");
  console.log("  ETH/USD Max Staleness:", ethUsdMaxStaleness, "seconds");
  console.log("═══════════════════════════════════════════════════\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
