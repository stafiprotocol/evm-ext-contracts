// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ICCIPSender {
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data
    ) external returns (bytes32 messageId);
}