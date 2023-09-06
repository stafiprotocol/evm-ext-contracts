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

### [Supported Networks](https://docs.chain.link/ccip/supported-networks)

| Chain           | Router Address                             | Chain Selector       | Link Address                               |
| --------------- | ------------------------------------------ | -------------------- | ------------------------------------------ |
| ETH sepolia     | 0xD0daae2231E9CB96b94C8512223533293C3693Bf | 16015286601757825753 | 0x779877A7B0D9E8603169DdbD7836e478b4624789 |
| Arbitrum Goerli | 0x88E492127709447A5ABEFdaB8788a15B4567589E | 6101244977088475029  |                                            |
| Polygon Mumbai  | 0x70499c328e1E2a3c41108bd3730F6670a44595D1 | 12532609583862916517 |                                            |
