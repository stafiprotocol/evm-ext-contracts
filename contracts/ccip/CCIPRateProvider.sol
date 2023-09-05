// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interface/ICCIPRateProvider.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract CCIPRateProvider is ICCIPRateProvider, OwnerIsCreator {
    address receiver;

    uint256 rate;

    modifier onlyReceiver() {
        if (receiver != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function setReceiver(address _receiver) external onlyOwner {
        if (receiver != address(0)) {
            revert ReceiverExists();
        }
        receiver = _receiver;
    }

    function setRate(uint256 _rate) external onlyReceiver {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}
