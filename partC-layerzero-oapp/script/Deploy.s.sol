// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrossChainMessenger.sol";

/**
 * @title Deploy
 * @dev Deployment script for CrossChainMessenger on either Optimism Sepolia or Arbitrum Sepolia.
 *
 * L2-15: Deploys the OApp and connects it to the LayerZero endpoint on the target chain.
 *
 * LayerZero V2 Endpoint Addresses (Sepolia Testnets):
 *   - Optimism Sepolia: 0x6EDCE65403992e310A62460808c4b910D972f10f
 *   - Arbitrum Sepolia: 0x6EDCE65403992e310A62460808c4b910D972f10f
 *
 * LayerZero Endpoint IDs:
 *   - Optimism Sepolia: 40232
 *   - Arbitrum Sepolia: 40231
 */
contract DeployScript is Script {
    // LayerZero V2 Endpoint (same address on both Optimism and Arbitrum Sepolia)
    address constant LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the CrossChainMessenger with the LZ endpoint and deployer as owner
        CrossChainMessenger messenger = new CrossChainMessenger(
            LZ_ENDPOINT,
            deployer
        );

        console.log("CrossChainMessenger deployed at:", address(messenger));
        console.log("Owner:", deployer);
        console.log("LZ Endpoint:", LZ_ENDPOINT);

        vm.stopBroadcast();
    }
}
