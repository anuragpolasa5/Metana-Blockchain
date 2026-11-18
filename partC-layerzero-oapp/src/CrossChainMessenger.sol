// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainMessenger
 * @dev An Omnichain Application (OApp) that sends and receives messages between two chains
 *      using the LayerZero V2 protocol.
 *
 * L2-11: Inherits from OApp.sol (LayerZero devtools).
 * L2-12: Implements sendMessage using _lzSend and _lzReceive for cross-chain messaging.
 * L2-13: Trusted peers are configured via OApp's setPeer (mapping contract addresses across chains).
 * L2-14: Uses quoteSend to estimate fees and applies execution options (_options).
 */
contract CrossChainMessenger is OApp {
    using OptionsBuilder for bytes;

    /// @notice The last message received from a remote chain.
    string public lastMessage;

    /// @notice The source endpoint ID of the last received message.
    uint32 public lastSenderEid;

    /// @notice Emitted when a message is sent to a remote chain.
    event MessageSent(uint32 indexed dstEid, string message, bytes32 receiver);

    /// @notice Emitted when a message is received from a remote chain.
    event MessageReceived(uint32 indexed srcEid, bytes32 sender, string message);

    /**
     * @dev Constructor initializes the OApp with the LayerZero endpoint and owner.
     * @param _endpoint The LayerZero endpoint address on this chain.
     * @param _owner The owner of this contract (can set peers).
     *
     * L2-15: The endpoint connects this contract to the LayerZero protocol on the deployed chain.
     */
    constructor(
        address _endpoint,
        address _owner
    ) OApp(_endpoint, _owner) Ownable(_owner) {}

    /**
     * @notice Estimates the messaging fee for sending a message to a destination chain.
     * @param _dstEid The destination endpoint ID (chain identifier in LayerZero).
     * @param _message The message string to send.
     * @param _options Execution options (gas limit, native drop, etc.).
     * @return fee The estimated MessagingFee (nativeFee + lzTokenFee).
     *
     * L2-14: Uses the internal _quote function to estimate fees before sending.
     */
    function quoteSend(
        uint32 _dstEid,
        string memory _message,
        bytes calldata _options
    ) external view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_message);
        fee = _quote(_dstEid, payload, _options, false);
    }

    /**
     * @notice Sends a cross-chain message to the specified destination chain.
     * @param _dstEid The destination endpoint ID.
     * @param _message The message string to send.
     * @param _options Execution options (e.g., gas limit for destination execution).
     *
     * L2-12: Uses _lzSend to dispatch the message through LayerZero.
     * L2-14: Caller must provide sufficient msg.value to cover the messaging fee.
     *         Use quoteSend() to estimate the required fee before calling this function.
     */
    function sendMessage(
        uint32 _dstEid,
        string memory _message,
        bytes calldata _options
    ) external payable {
        // Encode the message as bytes payload
        bytes memory payload = abi.encode(_message);

        // Send the message via LayerZero using _lzSend
        // The msg.value covers the cross-chain messaging fee
        _lzSend(
            _dstEid,
            payload,
            _options,
            MessagingFee(msg.value, 0), // Fee: native token only, no LZ token
            payable(msg.sender)          // Refund address for excess fees
        );

        emit MessageSent(_dstEid, _message, peers[_dstEid]);
    }

    /**
     * @dev Internal function called by LayerZero when a message is received from a remote chain.
     * @param _origin The origin information (srcEid, sender, nonce).
     * @param _guid The unique message identifier.
     * @param _message The encoded message payload.
     * @param _executor The executor address.
     * @param _extraData Any extra data passed.
     *
     * L2-12: Handles incoming cross-chain messages via _lzReceive.
     * L2-13: Only messages from configured trusted peers (via setPeer) are accepted.
     *         The OApp base contract validates the sender against the peers mapping.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Decode the message payload
        string memory receivedMessage = abi.decode(_message, (string));

        // Store the received message and source chain info
        lastMessage = receivedMessage;
        lastSenderEid = _origin.srcEid;

        emit MessageReceived(_origin.srcEid, _origin.sender, receivedMessage);
    }

    /**
     * @notice Builds execution options with a specified gas limit.
     * @param _gasLimit The gas limit for execution on the destination chain.
     * @return options The encoded options bytes.
     *
     * L2-14: Helper to construct _options parameter with gas limits.
     */
    function buildOptions(uint128 _gasLimit) public pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gasLimit, 0);
    }
}
