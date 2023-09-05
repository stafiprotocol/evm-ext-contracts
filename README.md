# evm-ext-contracts

### Contract deploy

1. deploy Sender (router address https://docs.chain.link/ccip/supported-networks)
2. deploy Receiver
3. deploy automation contract RateSyncAutomation
   1. _ccipRegister: testnet 0xE16Df59B887e3Caa439E0b29B42bA2e7976FD8b2
   1. sender: the sender contract address
   2. _gapBlock: 2 or 3 Avoid Chainlink auto check triggering too fast and wasting the link token.
5. set Sender canSendAddr(address(RateSyncAutomation))
6. send link to Sender
7. use addDstChainContract() config RateSyncAutomation contracts that need to be listened to
   1. _dstChainId: https://docs.chain.link/ccip/supported-networks
   2. _sourceContract: contract address the source chain
   3. _dstContract: Destination Chain rtoken contract address
   4. _receiver: Destination Chain receiver contract address
8. register RateSyncAutomation to [chainlink Automation sepolia](https://automation.chain.link/sepolia)