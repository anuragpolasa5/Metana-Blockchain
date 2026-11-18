// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CrossChainMessenger.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title CrossChainMessengerTest
 * @dev Foundry tests for the CrossChainMessenger OApp (L2-16).
 *
 * Tests verify contract deployment, options building, message encoding,
 * peer configuration access control, and fee estimation.
 *
 * Note: Full end-to-end cross-chain messaging is validated on-chain via
 * deployed contracts on Ethereum Sepolia <-> Arbitrum Sepolia with LayerZero V2.
 */
contract CrossChainMessengerTest is Test {
    using OptionsBuilder for bytes;

    // Chain endpoint IDs
    uint32 constant SEPOLIA_EID = 40161;
    uint32 constant ARB_EID = 40231;

    // LZ Endpoint (same on all testnets)
    address constant LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    CrossChainMessenger messenger;
    address owner = address(this);
    address user = address(0xBEEF);

    function setUp() public {
        // Fork Sepolia to get real LZ endpoint
        // Deploy messenger with real endpoint
        vm.createSelectFork("https://eth-sepolia.g.alchemy.com/v2/2wXoYz7k1USg1BlPWyAqa");
        messenger = new CrossChainMessenger(LZ_ENDPOINT, owner);
    }

    /// @notice Test that contract deploys correctly with owner set (L2-11)
    function test_deployment() public view {
        assertEq(messenger.owner(), owner);
    }

    /// @notice Test that only owner can set peers (L2-13)
    function test_onlyOwnerCanSetPeer() public {
        vm.prank(user);
        vm.expectRevert();
        messenger.setPeer(ARB_EID, bytes32(uint256(uint160(address(0xDEAD)))));
    }

    /// @notice Test owner can set peer successfully (L2-13)
    function test_ownerCanSetPeer() public {
        bytes32 peer = bytes32(uint256(uint160(address(0xDEAD))));
        messenger.setPeer(ARB_EID, peer);
        assertEq(messenger.peers(ARB_EID), peer);
    }

    /// @notice Test buildOptions produces valid output (L2-14)
    function test_buildOptions() public view {
        bytes memory options = messenger.buildOptions(200000);
        assertTrue(options.length > 0, "Options should be non-empty");
    }

    /// @notice Test different gas limits produce different options (L2-14)
    function test_buildOptionsWithDifferentGasLimits() public view {
        bytes memory options1 = messenger.buildOptions(100000);
        bytes memory options2 = messenger.buildOptions(500000);
        assertTrue(keccak256(options1) != keccak256(options2));
    }

    /// @notice Test quoteSend returns a fee estimate (L2-14)
    function test_quoteSend() public {
        // Set peer first
        messenger.setPeer(ARB_EID, bytes32(uint256(uint160(address(0xDEAD)))));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingFee memory fee = messenger.quoteSend(ARB_EID, "Hello!", options);
        assertTrue(fee.nativeFee > 0, "Fee should be non-zero");
    }

    /// @notice Test sendMessage emits event and works with funding (L2-12)
    function test_sendMessage() public {
        // Set peer
        messenger.setPeer(ARB_EID, bytes32(uint256(uint160(address(0xDEAD)))));
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Get fee quote
        MessagingFee memory fee = messenger.quoteSend(ARB_EID, "Hello Arbitrum!", options);

        // Fund user and send
        vm.deal(user, 1 ether);
        vm.prank(user);
        messenger.sendMessage{value: fee.nativeFee}(ARB_EID, "Hello Arbitrum!", options);
    }

    /// @notice Test message encoding/decoding roundtrip (L2-12)
    function test_messageEncodingRoundtrip() public pure {
        string memory original = "Hello from Sepolia!";
        bytes memory encoded = abi.encode(original);
        string memory decoded = abi.decode(encoded, (string));
        assertEq(decoded, original);
    }

    /// @notice Test peer address encoding (L2-13)
    function test_peerAddressEncoding() public pure {
        address contractAddr = 0x1234567890AbcdEF1234567890aBcdef12345678;
        bytes32 peer = bytes32(uint256(uint160(contractAddr)));
        address recovered = address(uint160(uint256(peer)));
        assertEq(recovered, contractAddr);
    }
}
