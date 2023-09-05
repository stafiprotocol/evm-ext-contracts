// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interface/ISender.sol";

/// @title - A simple contract for sending string data across chains.
contract Sender is OwnerIsCreator, ISender {
    using EnumerableSet for EnumerableSet.AddressSet;

    IRouterClient router;

    LinkTokenInterface private linkToken;

    EnumerableSet.AddressSet sendAddresses;

    modifier onlySendAddress() {
        if (!sendAddresses.contains(msg.sender)) {
            revert TransferNotAllow();
        }
        _;
    }

    constructor(address _router, address _link) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        sendAddresses.add(msg.sender);
    }

    function withdrawLink(address _to) external onlyOwner {
        uint256 balance = linkToken.balanceOf(address(this));

        if (balance == 0) revert NotEnoughBalance(0, 0);

        linkToken.transfer(_to, balance);
    }

    function addSendAddress(address _addAddress) external onlyOwner {
        sendAddresses.add(_addAddress);
    }

    function removeSendAddress(address _removeAddress) external onlyOwner {
        sendAddresses.remove(_removeAddress);
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
    ) external onlySendAddress returns (bytes32 messageId) {
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
}
