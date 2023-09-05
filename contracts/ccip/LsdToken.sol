// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract LsdToken {
    uint256 private rate;

    // Construct
    constructor() {
        rate = 1;
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}
