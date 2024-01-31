// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "./interface/ICCIPRateProvider.sol";
import "./Types.sol";

contract RateReceiver is CCIPReceiver {
    error TransferNotAllow();

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        address destination,
        uint256 rate
    );

    bytes32 private lastReceivedMessageId; // Store the last received messageId.
    bytes private lastReceivedData; // Store the last received bytes data.

    address private allowSender;

    constructor(address _router, address _allowSender) CCIPReceiver(_router) {
        allowSender = _allowSender;
    }

    modifier onlyAllowSender() {
        if (allowSender != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override onlyAllowSender {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        lastReceivedData = any2EvmMessage.data;

        RateMsg memory rateMsg = abi.decode(lastReceivedData, (RateMsg));
        ICCIPRateProvider(rateMsg.destination).setRate(rateMsg.rate);

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            rateMsg.destination,
            rateMsg.rate
        );
    }

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return data The last received bytes data.
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, bytes memory data)
    {
        return (lastReceivedMessageId, lastReceivedData);
    }
}
