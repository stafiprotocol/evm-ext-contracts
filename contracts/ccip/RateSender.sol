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
    uint256 rethLastestRate;

    IRMAITCRate public rmatic;
    uint256 rmaticLastestRate;

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
    }

    function addRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner returns (bool) {
        bool ok = rethChainSelectors.add(_selector);
        if (ok) {
            rethRateInfoOf[_selector] = RateInfo(_receiver, _rateProvider);
        }
        return ok;
    }

    function removeRETHRateInfo(
        uint64 _selector
    ) external onlyOwner returns (bool) {
        bool ok = rethChainSelectors.remove(_selector);
        if (ok) {
            delete rethRateInfoOf[_selector];
        }
        return ok;
    }

    function updateRETHRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner returns (bool) {
        if (rethChainSelectors.contains(_selector)) {
            rethRateInfoOf[_selector] = RateInfo(_receiver, _rateProvider);
            return true;
        }
        return false;
    }

    function addRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner returns (bool) {
        bool ok = rmaticChainSelectors.add(_selector);
        if (ok) {
            rmaticRateInfoOf[_selector] = RateInfo(_receiver, _rateProvider);
        }
        return ok;
    }

    function removeRMATICRateInfo(
        uint64 _selector
    ) external onlyOwner returns (bool) {
        bool ok = rmaticChainSelectors.remove(_selector);
        if (ok) {
            delete rmaticRateInfoOf[_selector];
        }
        return ok;
    }

    function updateRMATICRateInfo(
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner returns (bool) {
        if (rmaticChainSelectors.contains(_selector)) {
            rmaticRateInfoOf[_selector] = RateInfo(_receiver, _rateProvider);
            return true;
        }
        return false;
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
        if (rethLastestRate != newRate) {
            taskType = 1;
        }
        newRate = rmatic.getRate();
        if (rmaticLastestRate != newRate) {
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
        rethLastestRate = reth.getExchangeRate();
        for (uint256 i = 0; i < rethChainSelectors.length(); i++) {
            uint256 selector = rethChainSelectors.at(i);
            RateInfo memory rethRateInfo = rethRateInfoOf[selector];

            RateMsg memory rateMsg = RateMsg(
                rethRateInfo.destination,
                rethLastestRate
            );

            sendMessage(
                uint64(selector),
                rethRateInfo.receiver,
                abi.encode(rateMsg)
            );
        }
    }

    function sendMATICRate() internal {
        rmaticLastestRate = rmatic.getRate();
        for (uint256 i = 0; i < rmaticChainSelectors.length(); i++) {
            uint256 selector = rmaticChainSelectors.at(i);
            RateInfo memory rmaticRateInfo = rmaticRateInfoOf[selector];

            RateMsg memory rateMsg = RateMsg(
                rmaticRateInfo.destination,
                rethLastestRate
            );

            sendMessage(
                uint64(selector),
                rmaticRateInfo.receiver,
                abi.encode(rateMsg)
            );
        }
    }
}
