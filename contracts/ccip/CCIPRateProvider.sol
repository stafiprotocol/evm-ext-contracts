// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interface/ICCIPRateProvider.sol";

contract CCIPRateProvider is ICCIPRateProvider {
    address public receiver;

    uint256 rate;

    modifier onlyReceiver() {
        if (receiver != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    constructor(uint256 _rate, address _receiver) {
        rate = _rate;
        receiver = _receiver;
    }

    function setRate(uint256 _rate) external onlyReceiver {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}
