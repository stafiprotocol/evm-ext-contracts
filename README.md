# evm-ext-contracts

### Contract deploy

1. deploy UpgradeableSender
2. deploy UpgradeableReceiver
3. deploy automation contract RateSyncAutomation
4. set UpgradeableSender canSendAddr(address(RateSyncAutomation))
5. send link to UpgradeableSender.getInnerContract()
6. register RateSyncAutomation to [chainlink Automation sepolia](https://automation.chain.link/sepolia)