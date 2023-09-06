// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./interface/IRMAITCRate.sol";
import "./interface/IRETHRate.sol";
import "./interface/IRateSender.sol";
import "./Types.sol";


/// @title - A contract for sending rate data across chains.
contract RateSender is
    AutomationCompatibleInterface,
    OwnerIsCreator,
    IRateSender
{
    address public ccipRegister;

    IRouterClient public router;

    LinkTokenInterface public linkToken;

    RateInfo public rethRateInfo;

    RateInfo public rmaticRateInfo;

    IRETHRate public reth;

    IRMAITCRate public rmatic;

    modifier onlyCCIPRegister() {
        if (ccipRegister != msg.sender) {
            revert TransferNotAllow();
        }
        _;
    }

    constructor(address _router, address _link, address _ccipRegister) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        ccipRegister = _ccipRegister;
    }

    function initRETH(
        address _rethSource,
        address _arbitrumReceiver,
        address _arbitrumRateProvider,
        uint64 _arbitrumSelector
    ) external onlyOwner {
        if (address(reth) != address(0)) revert InitCompleted();
        reth = IRETHRate(_rethSource);
        rethRateInfo.destination = _arbitrumRateProvider;
        rethRateInfo.receiver = _arbitrumReceiver;
        rethRateInfo.destinationChainSelector = _arbitrumSelector;
    }

    function initRMATIC(
        address _rmaticSource,
        address _polygonReceiver,
        address _polygonRateProvider,
        uint64 _polygonSelector
    ) external onlyOwner {
        if (address(rmatic) != address(0)) revert InitCompleted();
        rmatic = IRMAITCRate(_rmaticSource);
        rmaticRateInfo.destination = _polygonRateProvider;
        rmaticRateInfo.receiver = _polygonReceiver;
        rmaticRateInfo.destinationChainSelector = _polygonSelector;
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
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data
    ) internal {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: data, // ABI-encoded
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
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
        bytes32 messageId = router.ccipSend(
            destinationChainSelector,
            evm2AnyMessage
        );

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
    }

    /**
     * @notice Get list of addresses that are underfunded and return payload compatible with Chainlink Automation Network
     * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds
     */
    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint taskType = 0;
        uint256 newRate = reth.getExchangeRate();
        if (rethRateInfo.rate != newRate) {
            taskType = 1;
        }
        newRate = rmatic.getRate();
        if (rmaticRateInfo.rate != newRate) {
            taskType += 2;
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
            sendMATICRate();
        } else if (taskType == 3) {
            sendRETHRate();
            sendMATICRate();
        }
    }

    function sendRETHRate() internal {
        rethRateInfo.rate = reth.getExchangeRate();

        RateMsg memory rateMsg = RateMsg(
            rethRateInfo.destination,
            rethRateInfo.rate
        );

        sendMessage(
            rethRateInfo.destinationChainSelector,
            rethRateInfo.receiver,
            abi.encode(rateMsg)
        );
    }

    function sendMATICRate() internal {
        rmaticRateInfo.rate = rmatic.getRate();

        RateMsg memory rateMsg = RateMsg(
            rmaticRateInfo.destination,
            rmaticRateInfo.rate
        );

        sendMessage(
            rmaticRateInfo.destinationChainSelector,
            rmaticRateInfo.receiver,
            abi.encode(rateMsg)
        );
    }
}
