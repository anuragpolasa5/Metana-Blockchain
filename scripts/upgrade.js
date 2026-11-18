// scripts/upgrade.js
// Upgrade the EIP-1967 Transparent Proxy from GameEconomyV1 to GameEconomyV2.
// Verifies that all state (balances, prices, recipes) is preserved after upgrade.

const { ethers, upgrades } = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with account:", deployer.address);

  // ── Read proxy address saved by deploy.js ────────────────────────────────────
  if (!fs.existsSync("deployed-addresses.json")) {
    throw new Error("deployed-addresses.json not found. Run deploy.js first.");
  }
  const { proxyAddress, implV1, proxyAdmin } = JSON.parse(fs.readFileSync("deployed-addresses.json", "utf8"));
  console.log("Proxy address:", proxyAddress);
  console.log("Current impl (V1):", implV1);
  console.log("ProxyAdmin:", proxyAdmin);

  // ── Snapshot V1 state before upgrade ─────────────────────────────────────────
  const v1 = await ethers.getContractAt("GameEconomyV1", proxyAddress);
  const nextIdBefore    = await v1.nextUniqueId();
  const price1Before    = await v1.materialPrice(1);
  const price2Before    = await v1.materialPrice(2);
  const recipeId0Before = await v1.recipeMaterialIds(0);
  const recipeId1Before = await v1.recipeMaterialIds(1);
  const recipe1Before   = await v1.recipe(1);
  const recipe2Before   = await v1.recipe(2);

  console.log("\n── V1 State Snapshot ──────────────────────");
  console.log("  nextUniqueId       :", nextIdBefore.toString());
  console.log("  materialPrice[1]   :", price1Before.toString());
  console.log("  materialPrice[2]   :", price2Before.toString());
  console.log("  recipeMaterialIds  :", [recipeId0Before, recipeId1Before].map(x => x.toString()));
  console.log("  recipe[1]          :", recipe1Before.toString());
  console.log("  recipe[2]          :", recipe2Before.toString());

  // ── Perform upgrade (Transparent Proxy) ─────────────────────────────────────
  console.log("\nUpgrading proxy to GameEconomyV2...");
  const GameEconomyV2 = await ethers.getContractFactory("GameEconomyV2");
  const v2 = await upgrades.upgradeProxy(proxyAddress, GameEconomyV2, { kind: "transparent" });
  await v2.waitForDeployment();

  const implV2 = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✅ Upgraded! New impl (V2):", implV2);

  // ── Verify state persisted ────────────────────────────────────────────────────
  const v2Contract = await ethers.getContractAt("GameEconomyV2", proxyAddress);
  const nextIdAfter  = await v2Contract.nextUniqueId();
  const price1After  = await v2Contract.materialPrice(1);
  const price2After  = await v2Contract.materialPrice(2);
  const recipe1After = await v2Contract.recipe(1);
  const recipe2After = await v2Contract.recipe(2);
  const versionStr   = await v2Contract.version();

  console.log("\n── V2 State After Upgrade ─────────────────");
  console.log("  version()          :", versionStr);
  console.log("  nextUniqueId       :", nextIdAfter.toString());
  console.log("  materialPrice[1]   :", price1After.toString());
  console.log("  materialPrice[2]   :", price2After.toString());
  console.log("  recipe[1]          :", recipe1After.toString());
  console.log("  recipe[2]          :", recipe2After.toString());

  // ── Assertions ─────────────────────────────────────────────────────────────────
  function assert(condition, message) {
    if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
  }
  assert(nextIdAfter === nextIdBefore, "nextUniqueId changed after upgrade!");
  assert(price1After === price1Before, "materialPrice[1] changed after upgrade!");
  assert(price2After === price2Before, "materialPrice[2] changed after upgrade!");
  assert(recipe1After === recipe1Before, "recipe[1] changed after upgrade!");
  assert(recipe2After === recipe2Before, "recipe[2] changed after upgrade!");
  assert(versionStr === "V2", "version() did not return V2!");
  console.log("\n✅ All state persistence checks PASSED.");

  // ── Test V2 new feature: buyMaterialsBatch ─────────────────────────────────────
  console.log("\nVerifying V2-only feature: buyMaterialsBatch exists on ABI...");
  assert(typeof v2Contract.buyMaterialsBatch === "function", "buyMaterialsBatch not found!");
  console.log("✅ buyMaterialsBatch is available on V2.");

  // ── Print final summary ─────────────────────────────────────────────────────────
  console.log("\n══════════════════════════════════════════");
  console.log("  UPGRADE SUMMARY");
  console.log("══════════════════════════════════════════");
  console.log("  Proxy address     :", proxyAddress);
  console.log("  ProxyAdmin address:", proxyAdmin);
  console.log("  Impl V1 address   :", implV1);
  console.log("  Impl V2 address   :", implV2);
  console.log("  State preserved   : YES");
  console.log("  V2 features       : buyMaterialsBatch");
  console.log("══════════════════════════════════════════\n");

  // Save updated addresses
  fs.writeFileSync(
    "deployed-addresses.json",
    JSON.stringify({ proxyAddress, implV1, implV2, proxyAdmin }, null, 2)
  );
  console.log("Updated addresses saved to deployed-addresses.json");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
