// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


contract LsdToken {

    uint256 public Rate;

    // Construct
    constructor() {
        Rate = 1;
    }

    function setRate(uint256 _rate) external {
        Rate = _rate;
    }

}
