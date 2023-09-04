// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./interface/ILsdToken.sol";
import "./interface/ICCIPSender.sol";

struct RTokonRate {
    address sourceContract;
    address dstContract;
    uint64 dstChainId;
    address receiver;
    uint256 rate;
    uint256 lastExecutedBlock;
}

struct SyncContract {
    address dstContract;
    uint256 rate;
}

struct MapUint {
    mapping(address => RTokonRate) dstRTokenMap;
    address[] keys;
}

contract RateSyncAutomation is AutomationCompatibleInterface {
    error TransferNotAllow();

    error MapUintOperationError();

    error DstContrantExists();

    event SendMessage(
        bytes32 indexed messageId,
        address indexed dstContract,
        address indexed receiver,
        uint64 dstChainId,
        uint256 rate
    );

    uint256 public gapBlock;

    address public admin;

    address public ccipRegister;

    MapUint private mapUint;

    ICCIPSender private sender;

    // address is the source contract
    mapping(address => ILsdToken) public sourceRokenMap;

    constructor(address _ccipRegister, address _sender, uint256 _gapBlock) {
        admin = msg.sender;
        ccipRegister = _ccipRegister;
        sender = ICCIPSender(_sender);
        gapBlock = _gapBlock;
    }

    /**
     * @notice Reverts if called by anyone other than the contract admin.
     */
    modifier onlyAdmin() {
        if (admin != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    modifier onlyCCIPAutoMotion() {
        if (admin != msg.sender && ccipRegister != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    function setSender(address _sender) external onlyAdmin {
        sender = ICCIPSender(_sender);
    }

    function getDstMapItem(
        uint index
    ) external view returns (address, address, uint64, address, uint256) {
        RTokonRate memory data = mapUint.dstRTokenMap[mapUint.keys[index]];
        return (
            data.sourceContract,
            data.dstContract,
            data.dstChainId,
            data.receiver,
            data.rate
        );
    }

    function addDstChainContract(
        uint64 _dstChainId,
        address _sourceContract,
        address _dstContract,
        address _receiver
    ) external onlyAdmin {
        RTokonRate memory rTokenRate = RTokonRate(
            _sourceContract,
            _dstContract,
            _dstChainId,
            _receiver,
            0,
            0
        );

        // Check if the contracts are already added to avoid duplication
        if (mapUint.dstRTokenMap[_dstContract].dstChainId != 0) {
            revert DstContrantExists();
        }

        if (address(sourceRokenMap[_sourceContract]) == address(0)) {
            sourceRokenMap[_sourceContract] = ILsdToken(_sourceContract);
        }

        bool done = add(mapUint, _dstContract, rTokenRate);
        if (!done) {
            revert MapUintOperationError();
        }
    }

    function removeDstChainContract(address _dstContract) external onlyAdmin {
        bool done = subtract(mapUint, _dstContract);
        if (!done) {
            revert MapUintOperationError();
        }
    }

    function removeSourceContract(address _sourceContract) external onlyAdmin {
        delete sourceRokenMap[_sourceContract];
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
        for (uint i = 0; i < mapUint.keys.length; i++) {
            RTokonRate memory token = mapUint.dstRTokenMap[mapUint.keys[i]];
            if (block.number - token.lastExecutedBlock < gapBlock) {
                continue;
            }
            // dst rate != source rate
            uint256 newRate = sourceRokenMap[token.sourceContract].getRate();
            if (token.rate != newRate) {
                token.lastExecutedBlock = block.number;
                mapUint
                    .dstRTokenMap[token.dstContract]
                    .lastExecutedBlock = token.lastExecutedBlock;
                return (true, abi.encode(token));
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
        RTokonRate memory token = abi.decode(performData, (RTokonRate));

        uint256 newRate = sourceRokenMap[token.sourceContract].getRate();
        // dst rate != source rate
        if (token.rate != newRate) {
            SyncContract memory sc = SyncContract(token.dstContract, newRate);

            bytes32 messageId = sender.sendMessage(
                token.dstChainId,
                token.receiver,
                abi.encode(sc)
            );

            // update save data
            mapUint.dstRTokenMap[token.dstContract].rate = newRate;

            emit SendMessage(
                messageId,
                sc.dstContract,
                token.receiver,
                token.dstChainId,
                sc.rate
            );
        }
    }

    /**
     * @notice Receive funds
     */
    receive() external payable {}

    // Add a new RTokonRate or update an existing one
    function add(
        MapUint storage self,
        address itemId,
        RTokonRate memory rate
    ) internal returns (bool) {
        RTokonRate storage oldRate = self.dstRTokenMap[itemId];

        // If this is a new item, add its key to the keys array
        if (oldRate.dstChainId == 0 && rate.dstChainId != 0) {
            self.keys.push(itemId);
        }

        // Update the value in the mapping
        self.dstRTokenMap[itemId] = rate;
        return true;
    }

    // Remove an RTokonRate
    function subtract(
        MapUint storage self,
        address itemId
    ) internal returns (bool) {
        RTokonRate storage oldRate = self.dstRTokenMap[itemId];

        // If the item doesn't exist, exit
        if (oldRate.dstChainId == 0) {
            return false;
        }

        // Delete the item from the mapping
        delete self.dstRTokenMap[itemId];

        // Remove the key from the keys array
        uint256 kl = self.keys.length;
        if (kl > 0) {
            for (uint256 i = 0; i < kl; i++) {
                if (itemId == self.keys[i]) {
                    self.keys[i] = self.keys[kl - 1];
                    break;
                }
            }
        }
        self.keys.pop();
        return true;
    }
}
