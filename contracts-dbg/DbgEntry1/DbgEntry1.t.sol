// SPDX-License-Identifier: MIT
pragma solidity >=0.4.21 <0.9.0;

import "../../contracts/ccip/RateSyncAutomation.sol";

contract DbgEntry {
    event EvmPrint(string);

    constructor() {
        emit EvmPrint("DbgEntry.constructor");

        RateSyncAutomation rateSyncAutomation = new RateSyncAutomation(
            address(0xE16Df59B887e3Caa439E0b29B42bA2e7976FD8b2),
            address(0xfC2abd4f2c7E7E0E3001f3A80f866B800d049444),
            3
        );

        rateSyncAutomation.addDstChainContract(
            12532609583862916517,
            address(0x051B1969Fad35927093419149B899F968072f9AF),
            address(0xCDD95Ffe440062b1Ee5409f9b97B2f379ED09542),
            address(0x53008a754FcAcF1Bf200BcB0C268129943b9523A)
        );

        emit EvmPrint("DbgEntry return");
    }
}
