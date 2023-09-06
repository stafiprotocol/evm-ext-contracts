// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct RateInfo {
    address destination;
    address receiver;
}

struct RateMsg {
    address destination;
    uint256 rate;
}
