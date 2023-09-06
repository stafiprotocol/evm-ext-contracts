// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRateSender {
    error InitCompleted();
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

    function initRETH(
        address _rethSource,
        address _arbitrumReceiver,
        address _arbitrumRateProvider,
        uint64 _arbitrumSelector
    ) external;

    function initRMATIC(
        address _rmaticSource,
        address _polygonReceiver,
        address _polygonRateProvider,
        uint64 _polygonSelector
    ) external;

    function withdrawLink(address _to) external;
}
