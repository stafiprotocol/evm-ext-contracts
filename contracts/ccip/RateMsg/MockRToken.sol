// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRTokenRate} from "./interface/IRTokenRate.sol";
import {IRTokenExchangeRate} from "./interface/IRTokenExchangeRate.sol";

contract MockRToken is IRTokenExchangeRate, IRTokenRate, Ownable {
    uint256 private rate;

    event RateUpdated(uint256 newRate);

    constructor(uint256 _initialRate) Ownable(msg.sender) {
        rate = _initialRate;
    }

    function getExchangeRate() external view override returns (uint256) {
        return rate;
    }

    function getRate() external view override returns (uint256) {
        return rate;
    }

    function setRate(uint256 _newRate) external onlyOwner {
        rate = _newRate;
        emit RateUpdated(_newRate);
    }
}