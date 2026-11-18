// scripts/deploy.js
// Deploy GameEconomyV1 behind an EIP-1967 Transparent Proxy and configure initial state.

const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  // ── Deploy proxy + V1 implementation (Transparent Proxy) ────────────────────
  const GameEconomyV1 = await ethers.getContractFactory("GameEconomyV1");

  const BASE_URI = "https://game.example.com/api/token/{id}.json";

  console.log("\nDeploying GameEconomyV1 behind EIP-1967 Transparent Proxy...");
  const proxy = await upgrades.deployProxy(
    GameEconomyV1,
    [BASE_URI, deployer.address],
    { kind: "transparent", initializer: "initialize" }
  );
  await proxy.waitForDeployment();

  const proxyAddress = await proxy.getAddress();
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);

  console.log("\n✅ Proxy address (use this for all interactions):", proxyAddress);
  console.log("✅ V1 Implementation address:", implAddress);
  console.log("✅ ProxyAdmin address:", adminAddress);

  // ── Configure material prices (IDs 1, 2, 3) ────────────────────────────────
  console.log("\nSetting material prices...");
  // Material 1: 10 currency units each
  await (await proxy.setMaterialPrice(1, 10)).wait();
  console.log("  Material 1 price: 10 currency units");

  // Material 2: 20 currency units each
  await (await proxy.setMaterialPrice(2, 20)).wait();
  console.log("  Material 2 price: 20 currency units");

  // Material 3: 5 currency units each
  await (await proxy.setMaterialPrice(3, 5)).wait();
  console.log("  Material 3 price: 5 currency units");

  // ── Set initial recipe: 2× material1 + 1× material2 → unique item ───────────
  console.log("\nSetting active recipe: [material1 x2, material2 x1] → unique crafted item...");
  await (await proxy.setRecipe([1, 2], [2, 1])).wait();
  console.log("  Recipe set successfully.");

  // ── Print summary ────────────────────────────────────────────────────────────
  console.log("\n══════════════════════════════════════════");
  console.log("  DEPLOYMENT SUMMARY");
  console.log("══════════════════════════════════════════");
  console.log("  Proxy address     :", proxyAddress);
  console.log("  Impl V1 address   :", implAddress);
  console.log("  ProxyAdmin address:", adminAddress);
  console.log("  Currency price    :", ethers.formatEther(await proxy.CURRENCY_PRICE()), "ETH / unit");
  console.log("  nextUniqueId      :", (await proxy.nextUniqueId()).toString());
  console.log("══════════════════════════════════════════\n");

  // Write addresses to a file for the upgrade script to read
  const fs = require("fs");
  fs.writeFileSync(
    "deployed-addresses.json",
    JSON.stringify({ proxyAddress, implV1: implAddress, proxyAdmin: adminAddress }, null, 2)
  );
  console.log("Addresses saved to deployed-addresses.json");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
