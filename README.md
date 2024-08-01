# evm-ext-contracts

**[Supported Networks(Testnet)](https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#overview)**

## Contract(Rate CCIP Message) deploy

### manual deployment
1. deploy Receiver
2. deploy CCIPRateProvider (rate+address(Receiver))
3. deploy Sender (router address https://docs.chain.link/ccip/supported-networks)
   * deploy
   * addRTokenInfo
4. send link to Sender

### automatic deployment

```bash
cp ./scripts/RateMsg/test/config.example.json ./scripts/RateMsg/test/config.json
```

```bash
NETWORK_SOURCE=chain_source NETWORK_DESTINATION=chain_dst ./scripts/RateMsg/test/deploy_rate_msg_all.sh
```

### Configure RateSender at csip automation

[automation](https://automation.chain.link/)
