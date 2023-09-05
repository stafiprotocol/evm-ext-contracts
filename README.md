# evm-ext-contracts

### Contract deploy

1. deploy Sender (router address https://docs.chain.link/ccip/supported-networks)
2. deploy Receiver
3. deploy automation contract RateSyncAutomation
4. set Sender canSendAddr(address(RateSyncAutomation))
5. send link to Sender
6. use addDstChainContract() config RateSyncAutomation contracts that need to be listened to
   1. _dstChainId https://docs.chain.link/ccip/supported-networks
   2. _sourceContract contract address the source chain
   3. _dstContract Destination Chain rtoken contract address
   4. _receiver Destination Chain receiver contract address
7. register RateSyncAutomation to [chainlink Automation sepolia](https://automation.chain.link/sepolia)