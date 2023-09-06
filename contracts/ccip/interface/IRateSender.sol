// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRateSender {
    error InitCompleted();
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error TransferNotAllow();
    error SelectorExist();
    error SelectorNotExist();
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed sender,
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );

    function addRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external;

    function removeRETHRateInfo(uint64 _selector) external;

    function updateRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external;

    function addRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external;

    function removeRMATICRateInfo(uint64 _selector) external;

    function updateRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external;

    function withdrawLink(address _to) external;
}
