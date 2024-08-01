// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRateSender {
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error TransferNotAllow();
    error SelectorExist();
    error SelectorNotExist();
    error GasLimitTooLow();
    error InvalidContract(string param);
    error InvalidAddress(string param);

    enum RateSourceType {
        RATE,
        EXCHANGE_RATE
    }

    event RTokenInfoAdded(string tokenName, address rateSource, RateSourceType sourceType);
    event RTokenInfoUpdated(string tokenName, address rateSource, RateSourceType sourceType);
    event MessageSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address sender,
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );
    event RTokenInfoRemoved(string indexed tokenName);
    event RTokenDstInfoAdded(string tokenName, address receiver, address rateProvider, uint64 selector);
    event RTokenDstRemoved(string indexed tokenName, uint64 indexed selector);
    event RTokenDstInfoUpdated(
        string indexed tokenName,
        address receiver,
        address dstRateProvider,
        uint64 indexed selector
    );
}
