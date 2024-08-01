// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRateSender} from "./interface/IRateSender.sol";
import {IRTokenRate} from "./interface/IRTokenRate.sol";
import {IRTokenExchangeRate} from "./interface/IRTokenExchangeRate.sol";
import {RateMsg, RateInfo} from "./Types.sol";

/// @title RateSender - An upgradeable contract for sending rate data across chains
/// @notice This contract allows for the management and cross-chain transmission of token exchange rates
/// @dev Implements Chainlink's CCIP for cross-chain communication and Automation for regular updates
contract RateSender is Initializable, AccessControlUpgradeable, PausableUpgradeable, AutomationCompatibleInterface, IRateSender {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Struct to store information about a token's rate
    struct TokenRateInfo {
        address rateSource;               // Address of the rate source contract
        RateSourceType sourceType;        // Type of the rate source (RATE or EXCHANGE_RATE)
        uint256 latestRate;               // Latest recorded rate for the token
        EnumerableSet.UintSet chainSelectors; // Set of chain selectors where this rate should be sent
    }

    IRouterClient public router;          // Chainlink's CCIP router
    IERC20 public linkToken;              // LINK token used for paying fees

    mapping(string => TokenRateInfo) private tokenRateInfos; // Mapping of token names to their rate info
    mapping(string => mapping(uint256 => RateInfo)) private rateInfoOf; // Mapping of token names and chain selectors to rate info
    string[] public tokenNames;           // List of all token names added to the contract

    uint256 public gasLimit;              // Gas limit for cross-chain transactions
    bytes public extraArgs;               // Extra arguments for CCIP messages
    bool public useExtraArgs;             // Flag to determine whether to use extra arguments
    

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @dev This function replaces the constructor for upgradeable contracts
    /// @param _router Address of the CCIP router
    /// @param _link Address of the LINK token
    /// @param _admin Address of the initial admin
    function initialize(address _router, address _link, address _admin) public initializer {
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        gasLimit = 600_000;
        useExtraArgs = false;
    }

    /// @notice Pause the contract
    /// @dev Only addresses with PAUSER_ROLE can call this function
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    /// @dev Only addresses with PAUSER_ROLE can call this function
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Sets a new router address
    /// @param _router New router address
    function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
        router = IRouterClient(_router);
    }

    /// @notice Adds a new token rate to be tracked
    /// @param tokenName Name of the token
    /// @param rateSource Address of the rate source contract
    /// @param sourceType Type of the rate source
    function addTokenRate(string memory tokenName, address rateSource, RateSourceType sourceType) external onlyRole(ADMIN_ROLE) {
        require(tokenRateInfos[tokenName].rateSource == address(0), "Token rate already exists");
        tokenRateInfos[tokenName].rateSource = rateSource;
        tokenRateInfos[tokenName].sourceType = sourceType;
        tokenNames.push(tokenName);
        emit TokenRateAdded(tokenName, rateSource, sourceType);
    }

    /// @notice Sets the gas limit for cross-chain transactions
    /// @param _gasLimit New gas limit
    function setGasLimit(uint256 _gasLimit) external onlyRole(ADMIN_ROLE) {
        if (_gasLimit < 200_000) {
            revert GasLimitTooLow();
        }
        gasLimit = _gasLimit;
    }

    /// @notice Sets extra arguments for CCIP messages
    /// @param _extraArgs New extra arguments
    /// @param _useExtraArgs Flag to use the extra arguments
    function setExtraArgs(bytes memory _extraArgs, bool _useExtraArgs) external onlyRole(ADMIN_ROLE) {
        extraArgs = _extraArgs;
        useExtraArgs = _useExtraArgs;
    }

    /// @notice Adds rate information for a specific token and chain
    /// @param tokenName Name of the token
    /// @param _receiver Address of the receiver on the destination chain
    /// @param _rateProvider Address of the rate provider on the destination chain
    /// @param _selector Chain selector for the destination chain
    function addRateInfo(
        string memory tokenName,
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyRole(ADMIN_ROLE) {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        require(tokenInfo.rateSource != address(0), "Token rate not found");
        if (!tokenInfo.chainSelectors.add(_selector)) revert SelectorExist();
        rateInfoOf[tokenName][_selector] = RateInfo({receiver: _receiver, destination: _rateProvider});
    }

    /// @notice Removes rate information for a specific token and chain
    /// @param tokenName Name of the token
    /// @param _selector Chain selector to remove
    function removeRateInfo(string memory tokenName, uint64 _selector) external onlyRole(ADMIN_ROLE) {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (!tokenInfo.chainSelectors.remove(_selector)) revert SelectorNotExist();
        delete rateInfoOf[tokenName][_selector];
    }

    /// @notice Updates rate information for a specific token and chain
    /// @param tokenName Name of the token
    /// @param _receiver New receiver address
    /// @param _rateProvider New rate provider address
    /// @param _selector Chain selector to update
    function updateRateInfo(
        string memory tokenName,
        address _receiver,
        address _rateProvider,
        uint64 _selector
    ) external onlyRole(ADMIN_ROLE) {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (!tokenInfo.chainSelectors.contains(_selector)) revert SelectorNotExist();
        rateInfoOf[tokenName][_selector] = RateInfo({receiver: _receiver, destination: _rateProvider});
    }

    /// @notice Withdraws LINK tokens from the contract
    /// @param _to Address to send the LINK tokens to
    function withdrawLink(address _to) external onlyRole(ADMIN_ROLE) {
        uint256 balance = linkToken.balanceOf(address(this));
        if (balance == 0) revert NotEnoughBalance(0, 0);
        require(linkToken.transfer(_to, balance), "Transfer failed");
    }

    /// @notice Internal function to send a CCIP message
    /// @param destinationChainSelector Chain selector for the destination chain
    /// @param receiver Address of the receiver on the destination chain
    /// @param data Encoded data to be sent
    function sendMessage(uint64 destinationChainSelector, address receiver, bytes memory data) internal {
        bytes memory thisExtraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit}));
        if (useExtraArgs) {
            thisExtraArgs = extraArgs;
        }
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: thisExtraArgs,
            feeToken: address(linkToken)
        });

        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);
        }

        linkToken.approve(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        emit MessageSent(messageId, destinationChainSelector, msg.sender, receiver, data, address(linkToken), fees);
    }

    /// @notice Internal function to get the current rate for a token
    /// @param tokenName Name of the token
    /// @return Current rate of the token
    function getRate(string memory tokenName) internal view returns (uint256) {
        TokenRateInfo storage tokenInfo = tokenRateInfos[tokenName];
        if (tokenInfo.sourceType == RateSourceType.RATE) {
            return IRTokenRate(tokenInfo.rateSource).getRate();
        } else {
            return IRTokenExchangeRate(tokenInfo.rateSource).getExchangeRate();
        }
    }

    /// @notice Chainlink Automation compatible function to check if upkeep is needed
    /// @return upkeepNeeded Boolean indicating if upkeep is needed
    /// @return performData Encoded data to be used in performUpkeep function
    function checkUpkeep(
        bytes calldata
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint i = 0; i < tokenNames.length; i++) {
            TokenRateInfo storage tokenInfo = tokenRateInfos[tokenNames[i]];
            uint256 newRate = getRate(tokenNames[i]);
            if (tokenInfo.latestRate != newRate && tokenInfo.chainSelectors.length() > 0) {
                return (true, abi.encode(tokenNames[i]));
            }
        }
        return (false, bytes(""));
    }

    /// @notice Chainlink Automation compatible function to perform upkeep
    /// @param performData Encoded data from checkUpkeep
    function performUpkeep(bytes calldata performData) external override whenNotPaused {
        string memory tokenName = abi.decode(performData, (string));
        sendTokenRate(tokenName);
    }

    /// @notice Internal function to send token rate to all registered chains
    /// @param tokenName Name of the token to send rate for
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