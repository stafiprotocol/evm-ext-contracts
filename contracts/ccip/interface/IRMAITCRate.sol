// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRMAITCRate {
    function getRate() external view returns (uint256);
}
