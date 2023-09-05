// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract LsdToken {
    uint256 private Rate;

    // Construct
    constructor() {
        Rate = 1;
    }

    function setRate(uint256 _rate) external {
        Rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return Rate;
    }
}
