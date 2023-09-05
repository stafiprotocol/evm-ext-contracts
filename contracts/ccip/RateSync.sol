// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./interface/ILsdToken.sol";
import "./interface/ISender.sol";
import "./interface/IRateSync.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

struct TokenInfo {
    address source;
    address destination;
    uint64 destinationChainSelector;
    address receiver;
    uint256 rate;
    uint256 lastCheckedBlock;
}

struct SyncMsg {
    address destination;
    uint256 rate;
}

contract RateSync is AutomationCompatibleInterface, OwnerIsCreator,IRateSync {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public gapBlock;

    address public ccipRegister;

    ISender private sender;

    mapping(address => ILsdToken) public sourceTokenOf;

    mapping(address => TokenInfo) public destinationTokenOf;

    EnumerableSet.AddressSet destinationTokens;

    constructor(address _ccipRegister, address _sender, uint256 _gapBlock) {
        ccipRegister = _ccipRegister;
        sender = ISender(_sender);
        gapBlock = _gapBlock;
    }

    modifier onlyCCIPAutoMotion() {
        if (ccipRegister != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    function setSender(address _sender) external onlyOwner {
        sender = ISender(_sender);
    }

    function addDestinationToken(
        uint64 _destinationChainSelector,
        address _source,
        address _destination,
        address _receiver
    ) external onlyOwner {
        TokenInfo memory tokenInfo = TokenInfo(
            _source,
            _destination,
            _destinationChainSelector,
            _receiver,
            0,
            0
        );

        // Check if the contracts are already added to avoid duplication
        if (destinationTokenOf[_destination].destinationChainSelector != 0) {
            revert DestinationExists();
        }
        destinationTokenOf[_destination] = tokenInfo;
        destinationTokens.add(_destination);

        if (address(sourceTokenOf[_source]) == address(0)) {
            sourceTokenOf[_source] = ILsdToken(_source);
        }
    }

    function removeDestinationToken(address _destination) external onlyOwner {
        delete destinationTokenOf[_destination];
        destinationTokens.remove(_destination);
    }

    function removeSourceToken(address _source) external onlyOwner {
        delete sourceTokenOf[_source];
    }

    /**
     * @notice Get list of addresses that are underfunded and return payload compatible with Chainlink Automation Network
     * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds
     */
    function checkUpkeep(
        bytes calldata
    )
        external
        override
        onlyCCIPAutoMotion
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint i = 0; i < destinationTokens.length(); i++) {
            TokenInfo memory tokenInfo = destinationTokenOf[
                destinationTokens.at(i)
            ];
            if (block.number - tokenInfo.lastCheckedBlock < gapBlock) {
                continue;
            }
            // destination rate != source rate
            uint256 newRate = sourceTokenOf[tokenInfo.source].getRate();
            if (tokenInfo.rate != newRate) {
                tokenInfo.lastCheckedBlock = block.number;
                destinationTokenOf[tokenInfo.destination]
                    .lastCheckedBlock = tokenInfo.lastCheckedBlock;
                return (true, abi.encode(tokenInfo));
            }
        }
        return (false, bytes(""));
    }

    /**
     * @notice Called by Chainlink Automation Node to send funds to underfunded addresses
     * @param performData The abi encoded list of addresses to fund
     */
    function performUpkeep(
        bytes calldata performData
    ) external override onlyCCIPAutoMotion {
        TokenInfo memory tokenInfo = abi.decode(performData, (TokenInfo));

        uint256 newRate = sourceTokenOf[tokenInfo.source].getRate();
        // destination rate != source rate
        if (tokenInfo.rate != newRate) {
            SyncMsg memory syncMsg = SyncMsg(tokenInfo.destination, newRate);

            bytes32 messageId = sender.sendMessage(
                tokenInfo.destinationChainSelector,
                tokenInfo.receiver,
                abi.encode(syncMsg)
            );

            // update token save rate
            destinationTokenOf[tokenInfo.destination].rate = newRate;

            emit SendMessage(
                messageId,
                syncMsg.destination,
                tokenInfo.receiver,
                tokenInfo.destinationChainSelector,
                syncMsg.rate
            );
        }
    }
}
