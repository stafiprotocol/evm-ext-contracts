# evm-ext-contracts

### Contract deploy

1. deploy Receiver
2. deploy CCIPRateProvider (rate+address(Receiver))
3. deploy Sender (router address https://docs.chain.link/ccip/supported-networks)
   * deploy
   * addRETHRateInfo
   * addMATICRateInfo
4. send link to Sender
5. register Sender to [chainlink Automation sepolia](https://automation.chain.link/sepolia)
   * CCIP Registry(ETH sepolia) 0xE16Df59B887e3Caa439E0b29B42bA2e7976FD8b2

### [Supported Networks(Testnet)](https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#overview)


| Chain            | Router Address                             | Chain Selector       | Link Address                               |
| ---------------- | ------------------------------------------ | -------------------- | ------------------------------------------ |
| Ethereum sepolia | 0x0bf3de8c5d3e8a2b34d2beeb17abfcebaf363a59 | 16015286601757825753 | 0x779877A7B0D9E8603169DdbD7836e478b4624789 |
| Arbitrum sepolia | 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 | 3478487238524512106  | 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E |
| Polygon Mumbai   | 0x1035CabC275068e0F4b745A29CEDf38E13aF41b1 | 12532609583862916517 | 0x326C977E6efc84E512bB9C30f76E30c160eD06FB |
