// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ILsdToken {
    function setRate(uint256 _rate) external;

    function Rate() external view returns (uint256);
}
