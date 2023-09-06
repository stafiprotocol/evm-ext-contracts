// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IRETHRate {
    function getExchangeRate() external view returns (uint256);
}
