// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRTokenRate {
    function getRate() external view returns (uint256);
}
