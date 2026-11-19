// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrossChainMessenger.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title SendMessage
 * @dev Script to send a cross-chain message using the deployed CrossChainMessenger.
 *
 * L2-12: Demonstrates sending a message from one chain to another.
 * L2-14: Uses quoteSend to estimate fees and applies gas limit options.
 */
contract SendMessageScript is Script {
    using OptionsBuilder for bytes;

    function run() external {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        address messengerAddress = vm.envAddress("MESSENGER_ADDRESS");
        uint32 dstEid = uint32(vm.envUint("DST_EID"));
        string memory message = vm.envString("MESSAGE");

        vm.startBroadcast(senderPrivateKey);

        CrossChainMessenger messenger = CrossChainMessenger(messengerAddress);

        // L2-14: Build execution options with 200,000 gas limit for destination
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // L2-14: Estimate the messaging fee
        MessagingFee memory fee = messenger.quoteSend(dstEid, message, options);
        console.log("Estimated native fee:", fee.nativeFee);

        // L2-12: Send the message with the estimated fee
        messenger.sendMessage{value: fee.nativeFee}(dstEid, message, options);

        console.log("Message sent successfully!");
        console.log("Destination EID:", dstEid);
        console.log("Message:", message);

        vm.stopBroadcast();
    }
}
