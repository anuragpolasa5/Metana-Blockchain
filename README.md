# Bmodule-13: Gold Asset Token (GXAU)

Solidity smart contract that represents gold on-chain using Chainlink price feeds. 1 GXAU is denominated as 1 ounce of gold and priced through XAU/USD and ETH/USD oracles; the contract does not itself provide custody or redemption of physical gold.

## What it does

- ERC20 token priced from Chainlink XAU/USD and ETH/USD feeds
- Minting gated by a configurable threshold that deployment derives from the live gold price
- Mint cost paid in ETH after USD-to-ETH oracle conversion
- Independent freshness windows for XAU/USD and ETH/USD
- Per-feed sanity bands that reject implausible XAU or ETH prices
- 18-decimal normalized price history with Chainlink Automation-compatible upkeep functions
- Internal 18-decimal normalization regardless of feed decimal format

## Requirements covered

| ID | What | Where |
|---|---|---|
| RWA-01 | ERC20 token representing gold | `constructor` |
| RWA-02 | Live price from Chainlink XAU/USD | `getLatestPrice()` |
| RWA-03 | Display price in USD | `getAssetPriceUSD()` |
| RWA-04 | Conditional minting + dynamic cost | `mint()` |
| RWA-05 | Price history + automation trigger | `performUpkeep()`, `updatePriceHistory()` |

## Oracle safety

Both feeds are normalized to 18 decimals and checked for complete rounds, positive answers, future timestamps, staleness, and plausible price ranges. XAU/USD accepts `$500–$20,000`; ETH/USD accepts `$100–$100,000`. Each feed has its own owner-updatable staleness setting because their heartbeats differ.

The Sepolia deployment settings are based on the specific Chainlink feed pages:

- [XAU/USD on Ethereum Sepolia](https://data.chain.link/feeds/ethereum-testnet/sepolia/xau-usd): 24-hour heartbeat, so the default maximum age is 48 hours.
- [ETH/USD on Ethereum Sepolia](https://data.chain.link/feeds/ethereum-testnet/sepolia/eth-usd): 1-hour heartbeat, so the default maximum age is 2 hours.

`deploy.js` enforces a minimum of twice each heartbeat. It also reads XAU/USD before deployment and either derives the mint threshold at 110% of the live price or validates `MINT_THRESHOLD_USD` is above that price. A stale feed or unsafe setting aborts before broadcasting.

## What I learned

Working with Chainlink feeds was mostly about decimal discipline. XAU/USD and ETH/USD commonly return 8-decimal values, while the threshold and calculations use 18 decimals. Normalizing before comparison prevents mismatched-unit errors.

The ETH conversion uses ceiling division so the contract does not undercollect. Automation uses a non-reverting validation path: unhealthy or out-of-band XAU data causes `performUpkeep` to skip the update, while user-facing reads return a descriptive custom error.

## Problems I ran into

**Decimal scaling** — Comparing raw feed values against 18-decimal thresholds made bad prices appear valid. Normalizing first fixed the checks and arithmetic.

**ETH conversion** — An early version treated USD and ETH as 1:1. The ETH/USD feed now converts the gold-denominated USD value into wei.

**Shared freshness limits** — XAU/USD and ETH/USD do not share a heartbeat. Separate limits now prevent one feed's schedule from weakening or breaking validation for the other.

**Unsafe deployment defaults** — A fixed threshold can already be below the live price, and a guessed staleness window can be shorter than a feed heartbeat. Deployment now derives or validates both from live/feed-specific data.

## Testing

Run the Hardhat compiler and test suite:

```powershell
npm install
npm run compile
npm test
```

The suite covers constructor validation, oracle reads, stale and invalid prices, mint pricing and refunds, threshold enforcement, upkeep timing, administrative controls, and feed replacement.

## Sepolia deployment

The reviewed `Bmodule-13` implementation from commit `d523bd5` was deployed and source-verified on Ethereum Sepolia on September 21, 2026.

| Item | Value |
|---|---|
| GoldAssetToken | [`0x63d1d21069c4b9aa99657d496b6e8c1e4efbb6d2`](https://sepolia.etherscan.io/address/0x63d1d21069c4b9aa99657d496b6e8c1e4efbb6d2#code) |
| Deployment transaction | [`0x613224527d4e550e1dc3520f2559ead90c2bd57872656fcb7621ea3ff2540f9e`](https://sepolia.etherscan.io/tx/0x613224527d4e550e1dc3520f2559ead90c2bd57872656fcb7621ea3ff2540f9e) |
| Owner | `0xA5D3235b2C2e469c858CcD177Fe51d6186b9DA85` |
| XAU/USD feed | [`0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea`](https://sepolia.etherscan.io/address/0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea) |
| ETH/USD feed | [`0x694AA1769357215DE4FAC081bf1f309aDC325306`](https://sepolia.etherscan.io/address/0x694AA1769357215DE4FAC081bf1f309aDC325306) |
| Mint threshold | `4802325000000000000000` (`$4,802.325`, 18 decimals) |
| Update interval | `300` seconds |
| XAU maximum staleness | `172800` seconds |
| ETH/USD maximum staleness | `7200` seconds |

Verified constructor arguments:

```text
(
  0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea,
  0x694AA1769357215DE4FAC081bf1f309aDC325306,
  4802325000000000000000,
  300,
  172800,
  7200
)
```

For a new deployment, keep credentials only in an untracked local environment and run:

```powershell
Copy-Item .env.example .env
# Fill PRIVATE_KEY and RPC settings. Optionally customize the validated settings.
npm run deploy:sepolia
```

By default, `deploy.js` derives the mint threshold as 110% of the live XAU/USD price and uses twice each documented feed heartbeat for the staleness limits. To verify another deployment, pass the exact values printed by the script:

```powershell
npx hardhat verify --network sepolia <ADDRESS> <XAU_FEED> <ETH_FEED> <THRESHOLD_18DP> <UPDATE_INTERVAL> <XAU_MAX_STALENESS> <ETH_MAX_STALENESS>
```
