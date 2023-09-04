// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/ILSDRToken.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

struct SyncContract {
    address dstContract;
    uint256 rate;
}

contract UpgradeableReceiver is Initializable {
    Receiver private innerContract;
    address private router;

    function getInnerContract() public view returns (address) {
        return address(innerContract);
    }

    function initialize(address _router, address _rtoken) public initializer {
        router = _router;
        innerContract = new Receiver(address(this), _rtoken);
    }

    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, bytes memory data)
    {
        return innerContract.getLastReceivedMessageDetails();
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return innerContract.supportsInterface(interfaceId);
    }

    function ccipReceive(Client.Any2EVMMessage calldata message) external {
        return innerContract.ccipReceive(message);
    }

    /// @notice Return the current router
    /// @return i_router address
    function getRouter() public view returns (address) {
        return router;
    }
}

/// @title - A simple contract for receiving string data across chains.
contract Receiver is CCIPReceiver {
    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        bytes data // The bytes data that was received.
    );

    error StrToUintErr(string);

    bytes32 private lastReceivedMessageId; // Store the last received messageId.
    bytes private lastReceivedData; // Store the last received bytes data.

    constructor(address _router, address _rtoken) CCIPReceiver(_router) {
        rToken = ILSDRToken(_rtoken);
    }

    // TODO: can upgrade rates for multiple contracts
    // address is dst contranct address
    // mapping(address => RTokonRate) dstRTokenMap;

    // address[] public lsdRokenAddresses;

    ILSDRToken rToken;

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        lastReceivedData = any2EvmMessage.data;

        SyncContract memory token = abi.decode(lastReceivedData, (SyncContract));
        rToken.setRate(token.rate);

        // TODO：emit rate 的值

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            lastReceivedData
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
