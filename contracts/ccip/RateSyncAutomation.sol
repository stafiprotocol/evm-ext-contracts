// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./interface/ILSDRToken.sol";
import "./interface/ICCIPSender.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

struct RTokonRate {
    address sourceContract;
    address dstContract;
    uint64 dstChainId;
    address receiver;
    uint256 rate;
}

struct SyncContract {
    address dstContract;
    uint256 rate;
}

// TODO: add remove map or edit map

contract RateSyncAutomation is AutomationCompatibleInterface, Initializable {
    event SendMessage(
        bytes32 indexed messageId,
        address indexed dstContract,
        address indexed receiver,
        uint64 dstChainId,
        uint256 rate
    );

    event CheckStatus(bool);

    address public admin;

    address public ccipRegister;

    IUpgradeableSender sender;

    error TransferNotAllow();

    // address is the source contract
    mapping(address => ILSDRToken) sourceRokenMap;

    // address is dst contranct address
    mapping(address => RTokonRate) dstRTokenMap;

    address[] public dstRokenAddresses;

    function initialize(
        address _ccipRegister,
        address _sender
    ) public initializer {
        admin = msg.sender;
        ccipRegister = _ccipRegister;
        sender = IUpgradeableSender(_sender);
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
        sender = IUpgradeableSender(_sender);
    }

    function addDstChainContract(
        uint64 _dst_chainId,
        address _source_contract,
        address _dst_contract,
        address _receiver
    ) external onlyAdmin {
        require(msg.sender == admin, "only admin can add dst chain contract");
        RTokonRate memory rTokenRate = RTokonRate(
            _source_contract,
            _dst_contract,
            _dst_chainId,
            _receiver,
            0
        );
        dstRTokenMap[_dst_contract] = rTokenRate;

        sourceRokenMap[_source_contract] = ILSDRToken(_source_contract);
        dstRokenAddresses.push(_dst_contract);
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
        for (uint i = 0; i < dstRokenAddresses.length; i++) {
            RTokonRate memory token = dstRTokenMap[dstRokenAddresses[i]];
            // dst rate != source rate
            uint256 newRate = sourceRokenMap[token.sourceContract].Rate();
            if (token.rate != newRate) {
                emit CheckStatus(true);
                return (true, abi.encode(token));
            }
        }
        emit CheckStatus(false);
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

        uint256 newRate = sourceRokenMap[token.sourceContract].Rate();
        // dst rate != source rate
        if (token.rate != newRate) {
            bytes memory data = abi.encode(
                SyncContract({dstContract: token.dstContract, rate: token.rate})
            );

            bytes32 messageId = sender.sendMessage(
                token.dstChainId,
                token.receiver,
                data
            );

            dstRTokenMap[token.dstContract].rate = token.rate;

            emit SendMessage(
                messageId,
                token.dstContract,
                token.receiver,
                token.dstChainId,
                token.rate
            );
        }
    }

    function testUpkeep(
        address _receiver,
        address _dstContract
    ) external onlyAdmin {
        SyncContract memory td = SyncContract({
            dstContract: _dstContract,
            rate: 12
        });
        bytes memory data = abi.encode(td);
        bytes32 messageId = sender.sendMessage(
            12532609583862916517,
            _receiver,
            data
        );
        emit SendMessage(
            messageId,
            _dstContract,
            _receiver,
            12532609583862916517,
            12
        );
    }

    /**
     * @notice Receive funds
     */
    receive() external payable {}
}
