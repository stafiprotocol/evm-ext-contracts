// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenTransferor - A production-ready contract for cross-chain token transfers
/// @notice This contract allows users to transfer tokens between different blockchains
/// @dev This contract uses OpenZeppelin's v5 upgradeable contract patterns
contract TokenTransferor is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IRouterClient private s_router;
    IERC20 private s_linkToken;

    mapping(uint64 => bool) public allowlistedChains;
    mapping(address => bool) public allowlistedTokens;

    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );
    event ChainAllowlistUpdated(uint64 chainSelector, bool allowed);
    event TokenAllowlistUpdated(address token, bool allowed);
    event EmergencyWithdraw(address token, address to, uint256 amount);

    error TransferAmountTooHigh(uint256 amount, uint256 maxAmount);

    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error InsufficientAllowance(uint256 currentAllowance, uint256 requiredAmount);
    error InsufficientLINKBalance(uint256 currentBalance, uint256 requiredAmount);
    error TokenNotAllowlisted(address token);
    error InvalidAddress(string param);
    error InvalidContract(string param);

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        if (!allowlistedChains[_destinationChainSelector]) {
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        }
        _;
    }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    /// @dev Modifier that checks if the token is allowlisted.
    /// @param _token The address of the token to check.
    modifier onlyAllowlistedToken(address _token) {
        if (!allowlistedTokens[_token]) {
            revert TokenNotAllowlisted(_token);
        }
        _;
    }

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
        if (_router == address(0)) revert InvalidAddress("router");
        if (_link == address(0)) revert InvalidAddress("link");
        if (_admin == address(0)) revert InvalidAddress("admin");

        // Basic contract existence check
        if (!_isContract(_router)) revert InvalidContract("router");
        if (!_isContract(_link)) revert InvalidContract("link");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        s_router = IRouterClient(_router);
        s_linkToken = IERC20(_link);
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

    /// @notice Update the allowlist status of a destination chain
    /// @dev Only addresses with ADMIN_ROLE can call this function
    /// @param _destinationChainSelector The selector of the destination chain
    /// @param _allowed Whether the chain is allowed
    function updateChainAllowlist(uint64 _destinationChainSelector, bool _allowed) external onlyRole(ADMIN_ROLE) {
        allowlistedChains[_destinationChainSelector] = _allowed;
        emit ChainAllowlistUpdated(_destinationChainSelector, _allowed);
    }

    /// @notice Update the allowlist status of a token
    /// @dev Only addresses with ADMIN_ROLE can call this function
    /// @param _token The address of the token
    /// @param _allowed Whether the token is allowed
    function updateTokenAllowlist(address _token, bool _allowed) external onlyRole(ADMIN_ROLE) {
        allowlistedTokens[_token] = _allowed;
        emit TokenAllowlistUpdated(_token, _allowed);
    }

    function transferTokens(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeToken
    )
        internal
        nonReentrant
        validateReceiver(_receiver)
        onlyAllowlistedToken(_token)
        onlyAllowlistedChain(_destinationChainSelector)
        returns (bytes32 messageId)
    {
        // Check if the contract has enough allowance to spend user's tokens
        uint256 currentAllowance = IERC20(_token).allowance(msg.sender, address(this));
        if (currentAllowance < _amount) {
            revert InsufficientAllowance(currentAllowance, _amount);
        }

        // Create an EVM2AnyMessage struct in memory
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(_receiver, _token, _amount, _feeToken);

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);

        // Check if the contract has enough balance to pay for the fees
        if (_feeToken == address(0)) {
            if (fees > address(this).balance) {
                revert NotEnoughBalance(address(this).balance, fees);
            }
        } else {
            uint256 linkBalance = IERC20(_feeToken).balanceOf(address(this));
            if (linkBalance < fees) {
                revert InsufficientLINKBalance(linkBalance, fees);
            }
            IERC20(_feeToken).safeIncreaseAllowance(address(s_router), fees);
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Approve the Router to spend tokens on contract's behalf
        IERC20(_token).safeIncreaseAllowance(address(s_router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = _feeToken == address(0)
            ? s_router.ccipSend{value: fees}(_destinationChainSelector, evm2AnyMessage)
            : s_router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit TokensTransferred(messageId, _destinationChainSelector, _receiver, _token, _amount, _feeToken, fees);

        return messageId;
    }

    /// @notice Transfer tokens to receiver on the destination chain.
    /// @notice Pay in native gas such as ETH on Ethereum or MATIC on Polgon.
    /// @notice the token must be in the list of supported tokens.
    /// @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return messageId The ID of the message that was sent.
    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external nonReentrant returns (bytes32 messageId) {
        return transferTokens(_destinationChainSelector, _receiver, _token, _amount, address(0));
    }

    /// @notice Transfer tokens to receiver on the destination chain.
    /// @notice pay in LINK.
    /// @notice the token must be in the list of supported tokens.
    /// @dev Assumes your contract has sufficient LINK tokens to pay for the fees.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return messageId The ID of the message that was sent.
    function transferTokensPayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external nonReentrant returns (bytes32 messageId) {
        return transferTokens(_destinationChainSelector, _receiver, _token, _amount, address(s_linkToken));
    }

    /// @notice Build a CCIP message
    /// @dev Internal function to create a CCIP message
    /// @param _receiver The address of the receiver
    /// @param _token The address of the token
    /// @param _amount The amount of tokens
    /// @param _feeTokenAddress The address of the token used for fees
    /// @return A CCIP message
    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});

        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: "",
                tokenAmounts: tokenAmounts,
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})),
                feeToken: _feeTokenAddress
            });
    }

    /// @notice Allows the contract admin to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the admin of the contract.
    /// @param _beneficiary The address to which the Ether should be transferred.
    function withdraw(address _beneficiary) public onlyRole(ADMIN_ROLE) {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the admin of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(address _beneficiary, address _token) public onlyRole(ADMIN_ROLE) {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }

    // Helper function to check if an address is a contract
    function _isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /// @notice Allow the contract to receive Ether
    receive() external payable {}
}
