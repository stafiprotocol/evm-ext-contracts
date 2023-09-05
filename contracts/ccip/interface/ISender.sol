// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISender {
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error TransferNotAllow();
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed sender,
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );

    function addSendAddress(address _addAddress) external;

    function removeSendAddress(address _removeAddress) external;

    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data
    ) external returns (bytes32 messageId);

    function withdrawLink(address _to) external;
}