// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

contract UpgradeableSender is Initializable {
    Sender private innerContract;

    address public admin;

    address public canSendAddr;

    error TransferNotAdmin();

    event LinkBalance(address, uint256);

    event SenderFrom(address);

    /**
     * @notice Reverts if called by anyone other than the contract admin.
     */
    modifier onlyAdmin() {
        if (admin != msg.sender) {
            revert TransferNotAdmin();
        }
        _;
    }

    modifier canSend() {
        if (msg.sender != admin && msg.sender != canSendAddr) {
            revert TransferNotAdmin();
        }
        _;
    }

    function initialize(address _router, address _link) public initializer {
        admin = msg.sender;
        innerContract = new Sender(_router, _link);
    }

    function upgradeInner(address _router, address _link) external onlyAdmin {
        innerContract = new Sender(_router, _link);
    }

    function setCanSendAddr(address _canSendAddr) external onlyAdmin {
        canSendAddr = _canSendAddr;
    }

    function sendLinkTo(address _to) external onlyAdmin {
        uint256 balance = innerContract.getLinkToken().balanceOf(address(this));

        emit LinkBalance(address(this), balance);

        require(balance > 0, "Not enough LINK tokens in MyUpgradeableSender");

        require(
            innerContract.getLinkToken().transfer(_to, balance),
            "LINK token transfer failed"
        );
    }

    function recycleLinkTo(address _to) external onlyAdmin {
        innerContract.sendLinkTo(_to);
    }

    function getInnerContract() external view onlyAdmin returns (address) {
        return address(innerContract);
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
        bytes calldata data
    ) external canSend returns (bytes32 messageId) {
        return
            innerContract.sendMessage(destinationChainSelector, receiver, data);
    }
}

/// @title - A simple contract for sending string data across chains.
contract Sender is OwnerIsCreator {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        bytes data, // The bytes data being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    event LinkBalance(address, uint256);

    IRouterClient router;

    LinkTokenInterface private linkToken;

    constructor(address _router, address _link) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
    }

    function getLinkToken()
        external
        view
        onlyOwner
        returns (LinkTokenInterface)
    {
        return linkToken;
    }

    function sendLinkTo(address _to) external onlyOwner {
        uint256 balance = linkToken.balanceOf(address(this));

        emit LinkBalance(address(this), balance);

        require(balance > 0, "Not enough LINK tokens in MyUpgradeableSender");

        require(linkToken.transfer(_to, balance), "LINK token transfer failed");
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
        bytes calldata data
    ) external onlyOwner returns (bytes32 messageId) {
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
            receiver,
            data,
            address(linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }
}
