# evm-ext-contracts

### Contract deploy

1. deploy Sender
2. deploy Receiver
3. deploy automation contract RateSyncAutomation
4. set Sender canSendAddr(address(RateSyncAutomation))
5. send link to Sender
6. register RateSyncAutomation to [chainlink Automation sepolia](https://automation.chain.link/sepolia)