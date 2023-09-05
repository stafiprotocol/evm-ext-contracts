// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRateSync {
    error DestinationExists();
    error MapUintOperationError();
    error TransferNotAllow();
    event SendMessage(
        bytes32 indexed messageId,
        address indexed destination,
        address indexed receiver,
        uint64 destinationChainSelector,
        uint256 rate
    );

    function addDestinationToken(
        uint64 _destinationChainSelector,
        address _source,
        address _destination,
        address _receiver
    ) external;

    function ccipRegister() external view returns (address);

    function destinationTokenOf(address)
        external
        view
        returns (
            address source,
            address destination,
            uint64 destinationChainSelector,
            address receiver,
            uint256 rate,
            uint256 lastCheckedBlock
        );

    function gapBlock() external view returns (uint256);

    function removeDestinationToken(address _destination) external;

    function removeSourceToken(address _source) external;

    function setSender(address _sender) external;
}