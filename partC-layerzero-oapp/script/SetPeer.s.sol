// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrossChainMessenger.sol";

/**
 * @title SetPeer
 * @dev Script to configure trusted peers between chains (L2-13).
 *
 * After deploying on both chains, run this script on each chain to register
 * the remote contract as a trusted peer. This ensures only valid sources are accepted.
 *
 * Usage:
 *   On Optimism Sepolia: Set peer to Arbitrum Sepolia contract address with Arbitrum's EID
 *   On Arbitrum Sepolia: Set peer to Optimism Sepolia contract address with Optimism's EID
 */
contract SetPeerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // These should be set as environment variables after deployment
        address messengerAddress = vm.envAddress("MESSENGER_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));
        address remoteMessenger = vm.envAddress("REMOTE_MESSENGER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        CrossChainMessenger messenger = CrossChainMessenger(messengerAddress);

        // L2-13: Configure the trusted peer for the remote chain
        // Convert address to bytes32 (left-padded)
        bytes32 peerBytes32 = bytes32(uint256(uint160(remoteMessenger)));
        messenger.setPeer(remoteEid, peerBytes32);

        console.log("Peer set successfully!");
        console.log("Local contract:", messengerAddress);
        console.log("Remote EID:", remoteEid);
        console.log("Remote peer:", remoteMessenger);

        vm.stopBroadcast();
    }
}
