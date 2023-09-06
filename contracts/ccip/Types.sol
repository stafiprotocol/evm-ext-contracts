// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct RateInfo {
    uint256 rate;
    address destination;
    uint64 destinationChainSelector;
    address receiver;
}

struct RateMsg {
    address destination;
    uint256 rate;
}