// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./interface/ICCIPRateProvider.sol";
import "./interface/ISender.sol";

struct TokenInfo {
    uint256 rate;
    uint256 lastCheckedBlock;
    address destination;
    uint64 destinationChainSelector;
    address receiver;
}

struct SyncMsg {
    address destination;
    uint256 rate;
}

/// @title - A simple contract for sending string data across chains.
contract Sender is AutomationCompatibleInterface, OwnerIsCreator, ISender {
    uint256 public gapBlock;

    address public ccipRegister;

    IRouterClient router;

    LinkTokenInterface linkToken;

    TokenInfo rethInfo;

    TokenInfo rmaticInfo;

    // TODO: change to source contract
    // TODO: sender provider use other contrat
    ICCIPRateProvider rethProvider;

    ICCIPRateProvider rmaticProvider;

    modifier onlyCCIPRegister() {
        if (ccipRegister != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    constructor(
        address _router,
        address _link,
        address _ccipRegister,
        uint256 _gapBlock
    ) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        ccipRegister = _ccipRegister;
        gapBlock = _gapBlock;
    }

    function initRETH(
        address _rethSource,
        address _arbitrumReciver,
        address _arbitrumRateProvider,
        uint64 _arbitrumSelector
    ) external onlyOwner {
        if (address(rethProvider) != address(0)) revert InitCompleted();
        rethProvider = ICCIPRateProvider(_rethSource);
        rethInfo.destination = _arbitrumRateProvider;
        rethInfo.receiver = _arbitrumReciver;
        rethInfo.destinationChainSelector = _arbitrumSelector;
    }

    function initRMATIC(
        address _rmaticSource,
        address _polygonReciver,
        address _polygonRateProvider,
        uint64 _polygonSelector
    ) external onlyOwner {
        if (address(rmaticProvider) != address(0)) revert InitCompleted();
        rmaticProvider = ICCIPRateProvider(_rmaticSource);
        rmaticInfo.destination = _polygonRateProvider;
        rmaticInfo.receiver = _polygonReciver;
        rmaticInfo.destinationChainSelector = _polygonSelector;
    }

    function withdrawLink(address _to) external onlyOwner {
        uint256 balance = linkToken.balanceOf(address(this));

        if (balance == 0) revert NotEnoughBalance(0, 0);

        linkToken.transfer(_to, balance);
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param receiver The address of the recipient on the destination blockchain.
    /// @param data The bytes data to be sent.
    /// @return messageId The ID of the message that was sent.
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data
    ) internal returns (bytes32 messageId) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: data, // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                // TODO:
                Client.EVMExtraArgsV1({gasLimit: 600_000, strict: false})
            ),
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: address(linkToken)
        });

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            destinationChainSelector,
            msg.sender,
            receiver,
            data,
            address(linkToken),
            fees
        );

        // Return the message ID
        return messageId;
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
        onlyCCIPRegister
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint taskType = 0;
        if (block.number - rethInfo.lastCheckedBlock >= gapBlock) {
            rethInfo.lastCheckedBlock = block.number;
            uint256 newRate = rethProvider.getRate();
            if (rethInfo.rate != newRate) {
                rethInfo.rate = newRate;
                taskType = 1;
            }
        }
        if (block.number - rmaticInfo.lastCheckedBlock >= gapBlock) {
            rmaticInfo.lastCheckedBlock = block.number;
            uint256 newRate = rethProvider.getRate();
            if (rmaticInfo.rate != newRate) {
                rmaticInfo.rate = newRate;
                taskType += 2;
            }
        }
        if (taskType > 0) {
            return (true, abi.encode(taskType));
        }
        return (false, bytes(""));
    }

    /**
     * @notice Called by Chainlink Automation Node to send funds to underfunded addresses
     * @param performData The abi encoded list of addresses to fund
     */
    function performUpkeep(
        bytes calldata performData
    ) external override onlyCCIPRegister {
        uint taskType = abi.decode(performData, (uint));
        if (taskType == 1) {
            sendRETHRate();
        } else if (taskType == 2) {
            sendRMATICRate();
        } else if (taskType == 3) {
            sendRETHRate();
            sendRMATICRate();
        }
    }

    function sendRETHRate() internal {
        uint256 newRate = rethProvider.getRate();
        sendRate(rethInfo, newRate);
    }

    function sendRMATICRate() internal {
        uint256 newRate = rmaticProvider.getRate();
        sendRate(rmaticInfo, newRate);
    }

    function sendRate(TokenInfo storage tokenInfo, uint256 newRate) internal {
        if (tokenInfo.rate != newRate) {
            SyncMsg memory syncMsg = SyncMsg(tokenInfo.destination, newRate);

            sendMessage(
                tokenInfo.destinationChainSelector,
                tokenInfo.receiver,
                abi.encode(syncMsg)
            );

            // update token save rate
            tokenInfo.rate = newRate;
        }
    }
}
