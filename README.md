# evm-ext-contracts

### Contract deploy

1. deploy Receiver
2. deploy CCIPRateProvider (rate+address(Receiver))
3. deploy Sender (router address https://docs.chain.link/ccip/supported-networks)
   * deploy + initRETH + initRMATIC
3. send link to Sender
4. register Sender to [chainlink Automation sepolia](https://automation.chain.link/sepolia)