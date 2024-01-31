// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
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
    using EnumerableSet for EnumerableSet.UintSet;

    address public ccipRegister;

    IRouterClient public router;

    LinkTokenInterface public linkToken;

    EnumerableSet.UintSet private rethChainSelectors;
    EnumerableSet.UintSet private rmaticChainSelectors;

    mapping(uint => RateInfo) public rethRateInfoOf;

    mapping(uint => RateInfo) public rmaticRateInfoOf;

    IRETHRate public reth;
    uint256 public rethLatestRate;

    IRMAITCRate public rmatic;
    uint256 public rmaticLatestRate;

    uint256 public gasLimit;
    bytes extraArgs;
    bool useExtraArgs;

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
        address _rethSource,
        address _rmaticSource
    ) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        ccipRegister = _ccipRegister;
        reth = IRETHRate(_rethSource);
        rmatic = IRMAITCRate(_rmaticSource);
        gasLimit = 600_000;
        useExtraArgs = false;
    }

    function setRouter(address _router) external onlyOwner {
        router = IRouterClient(_router);
    }

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        if (_gasLimit < 200_000) {
            revert GasLimitTooLow();
        }
        gasLimit = _gasLimit;
    }

    function setExtraArgs(
        bytes memory _extraArgs,
        bool _useExtraArgs
    ) external onlyOwner {
        extraArgs = _extraArgs;
        useExtraArgs = _useExtraArgs;
    }

    function addRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        if (!rethChainSelectors.add(_selector)) revert SelectorExist();
        rethRateInfoOf[_selector] = RateInfo({
            receiver: _receiver,
            destination: _rateProvider
        });
    }

    function removeRETHRateInfo(uint64 _selector) external onlyOwner {
        if (!rethChainSelectors.remove(_selector)) revert SelectorNotExist();
        delete rethRateInfoOf[_selector];
    }

    function updateRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        if (!rethChainSelectors.contains(_selector)) revert SelectorNotExist();
        rethRateInfoOf[_selector] = RateInfo({
            receiver: _receiver,
            destination: _rateProvider
        });
    }

    function addRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        if (!rmaticChainSelectors.add(_selector)) revert SelectorExist();
        rmaticRateInfoOf[_selector] = RateInfo({
            receiver: _receiver,
            destination: _rateProvider
        });
    }

    function removeRMATICRateInfo(uint64 _selector) external onlyOwner {
        if (!rmaticChainSelectors.remove(_selector)) revert SelectorNotExist();
        delete rmaticRateInfoOf[_selector];
    }

    function updateRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        if (!rmaticChainSelectors.contains(_selector))
            revert SelectorNotExist();
        rmaticRateInfoOf[_selector] = RateInfo({
            receiver: _receiver,
            destination: _rateProvider
        });
    }

    function withdrawLink(address _to) external onlyOwner {
        uint256 balance = linkToken.balanceOf(address(this));

        if (balance == 0) revert NotEnoughBalance(0, 0);

        linkToken.transfer(_to, balance);
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @param destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param receiver The address of the recipient on the destination blockchain.
    /// @param data The bytes data to be sent.
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory data
    ) internal {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        bytes memory thisExtraArgs = Client._argsToBytes(
            // Additional arguments, setting gas limit and non-strict sequencing mode
            Client.EVMExtraArgsV1({gasLimit: gasLimit})
        );
        if (useExtraArgs) {
            thisExtraArgs = extraArgs;
        }
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: data, // ABI-encoded
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: thisExtraArgs,
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
     * @notice Checks if the exchange rates for RETH or RMATIC have changed.
     * @return upkeepNeeded indicates if an update is required, performData is an ABI-encoded integer representing the task type.
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
        if (rethLatestRate != newRate && rethChainSelectors.length() > 0) {
            taskType = 1;
        }
        newRate = rmatic.getRate();
        if (rmaticLatestRate != newRate && rmaticChainSelectors.length() > 0) {
            taskType += 2;
        }
        if (taskType > 0) {
            return (true, abi.encode(taskType));
        }
        return (false, bytes(""));
    }

    /**
     * @notice Called by the Chainlink Automation Network to update RETH and/or RMATIC rates.
     * @param performData The ABI-encoded integer representing the type of task to perform.
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
        rethLatestRate = reth.getExchangeRate();
        for (uint256 i = 0; i < rethChainSelectors.length(); i++) {
            uint256 selector = rethChainSelectors.at(i);
            RateInfo memory rethRateInfo = rethRateInfoOf[selector];

            RateMsg memory rateMsg = RateMsg({
                destination: rethRateInfo.destination,
                rate: rethLatestRate
            });

            sendMessage(
                uint64(selector),
                rethRateInfo.receiver,
                abi.encode(rateMsg)
            );
        }
    }

    function sendMATICRate() internal {
        rmaticLatestRate = rmatic.getRate();
        for (uint256 i = 0; i < rmaticChainSelectors.length(); i++) {
            uint256 selector = rmaticChainSelectors.at(i);
            RateInfo memory rmaticRateInfo = rmaticRateInfoOf[selector];

            RateMsg memory rateMsg = RateMsg({
                destination: rmaticRateInfo.destination,
                rate: rmaticLatestRate
            });

            sendMessage(
                uint64(selector),
                rmaticRateInfo.receiver,
                abi.encode(rateMsg)
            );
        }
    }
}
