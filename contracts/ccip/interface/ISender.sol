// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISender {
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

    function ccipRegister() external view returns (address);

    function gapBlock() external view returns (uint256);

    function initRETH(
        address _rethSource,
        address _arbitrumReciver,
        address _arbitrumRateProvider,
        uint64 _arbitrumSelector
    ) external;

    function initRMATIC(
        address _rmaticSource,
        address _polygonReciver,
        address _polygonRateProvider,
        uint64 _polygonSelector
    ) external;

    function withdrawLink(address _to) external;
}
