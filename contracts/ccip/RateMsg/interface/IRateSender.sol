// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRateSender {
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error TransferNotAllow();
    error SelectorExist();
    error SelectorNotExist();
    error GasLimitTooLow();

    enum RateSourceType {
        RATE,
        EXCHANGE_RATE
    }

    event TokenRateAdded(string tokenName, address rateSource, RateSourceType sourceType);
    event RateInfoAdded(string tokenName, address receiver, address rateProvider, uint64 selector);
    event MessageSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address sender,
        address receiver,
        bytes data,
        address feeToken,
        uint256 fees
    );
}
