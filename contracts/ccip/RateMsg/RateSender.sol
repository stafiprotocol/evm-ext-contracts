// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRateSender} from "./interface/IRateSender.sol";
import {IRTokenRate} from "./interface/IRTokenRate.sol";
import {IRTokenExchangeRate} from "./interface/IRTokenExchangeRate.sol";
import {RateMsg, RateInfo} from "./Types.sol";

/// @title - A contract for sending rate data across chains.
contract RateSender is AutomationCompatibleInterface, OwnerIsCreator, IRateSender {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct TokenRateInfo {
        address rateSource;
        RateSourceType sourceType;
        uint256 latestRate;
        EnumerableSet.UintSet chainSelectors;
    }

    IRouterClient public router;
    IERC20 public linkToken;

    mapping(string => TokenRateInfo) private tokenRateInfos;
    mapping(string => mapping(uint256 => RateInfo)) private rateInfoOf;
    string[] public tokenNames;

    uint256 public gasLimit;
    bytes extraArgs;
    bool useExtraArgs;

    constructor(address _router, address _link) {
        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        gasLimit = 600_000;
        useExtraArgs = false;
    }

    function addTokenRate(string memory tokenName, address rateSource, RateSourceType sourceType) external onlyOwner {
        require(tokenRateInfos[tokenName].rateSource == address(0), "Token rate already exists");
        tokenRateInfos[tokenName].rateSource = rateSource;
        tokenRateInfos[tokenName].sourceType = sourceType;
        tokenNames.push(tokenName);
        emit TokenRateAdded(tokenName, rateSource, sourceType);
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

    function setExtraArgs(bytes memory _extraArgs, bool _useExtraArgs) external onlyOwner {
        extraArgs = _extraArgs;
        useExtraArgs = _useExtraArgs;
    }

    function addRateInfo(
        string memory tokenName,
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        require(tokenInfo.rateSource != address(0), "Token rate not found");
        if (!tokenInfo.chainSelectors.add(_selector)) revert SelectorExist();
        rateInfoOf[tokenName][_selector] = RateInfo({receiver: _receiver, destination: _rateProvider});
    }

    function removeRateInfo(string memory tokenName, uint64 _selector) external onlyOwner {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (!tokenInfo.chainSelectors.remove(_selector)) revert SelectorNotExist();
        delete rateInfoOf[tokenName][_selector];
    }

    function updateRateInfo(
        string memory tokenName,
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyOwner {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (!tokenInfo.chainSelectors.contains(_selector)) revert SelectorNotExist();
        rateInfoOf[tokenName][_selector] = RateInfo({receiver: _receiver, destination: _rateProvider});
    }

    function withdrawLink(address _to) external onlyOwner {
        uint256 balance = linkToken.balanceOf(address(this));
        if (balance == 0) revert NotEnoughBalance(0, 0);
        require(linkToken.transfer(_to, balance), "Transfer failed");
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @param destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param receiver The address of the recipient on the destination blockchain.
    /// @param data The bytes data to be sent.
    function sendMessage(uint64 destinationChainSelector, address receiver, bytes memory data) internal {
        bytes memory thisExtraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit}));
        if (useExtraArgs) {
            thisExtraArgs = extraArgs;
        }
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data, // ABI-encoded
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: thisExtraArgs,
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: address(linkToken)
        });

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);
        }

        linkToken.approve(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        emit MessageSent(messageId, destinationChainSelector, msg.sender, receiver, data, address(linkToken), fees);
    }

    function getRate(string memory tokenName) internal view returns (uint256) {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (tokenInfo.sourceType == RateSourceType.RATE) {
            return IRTokenRate(tokenInfo.rateSource).getRate();
        } else {
            return IRTokenExchangeRate(tokenInfo.rateSource).getExchangeRate();
        }
    }

    /**
     * @notice Checks if the exchange rates for RETH or RMATIC have changed.
     * @return upkeepNeeded indicates if an update is required, performData is an ABI-encoded integer representing the task type.
     */
    function checkUpkeep(
        bytes calldata
    ) external view override returns (bool upkeepNeeded, bytes memory /* performData */) {
        for (uint i = 0; i < tokenNames.length; i++) {
            TokenRateInfo storage tokenInfo = tokenRateInfos[tokenNames[i]];
            uint256 newRate = getRate(tokenNames[i]);
            if (tokenInfo.latestRate != newRate && tokenInfo.chainSelectors.length() > 0) {
                return (true, abi.encode(tokenNames[i]));
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        string memory tokenName = abi.decode(performData, (string));
        sendTokenRate(tokenName);
    }

    function sendTokenRate(string memory tokenName) internal {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        tokenInfo.latestRate = getRate(tokenName);
        uint256[] memory selectors = tokenInfo.chainSelectors.values();
        for (uint256 i = 0; i < selectors.length; i++) {
            uint256 selector = selectors[i];
            RateInfo memory rateInfo = rateInfoOf[tokenName][selector];

            RateMsg memory rateMsg = RateMsg({destination: rateInfo.destination, rate: tokenInfo.latestRate});

            sendMessage(uint64(selector), rateInfo.receiver, abi.encode(rateMsg));
        }
    }
}
