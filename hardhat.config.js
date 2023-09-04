require("@nomicfoundation/hardhat-toolbox");
// https://www.npmjs.com/package/@ericxstone/hardhat-blockscout-verify?activeTab=readme
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require('dotenv').config();
require("hardhat-gas-reporter");
require('solidity-coverage')

const { ProxyAgent, setGlobalDispatcher } = require('undici');
const proxyAgent = new ProxyAgent("http://127.0.0.1:7890")
setGlobalDispatcher(proxyAgent);

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.19",
    },
    defaultNetwork: "hardhat",
    networks: {
        goerli: {
            url: process.env.GOERLI_RPC,
            accounts: [process.env.PRIVATEKEY]
        },
        sepolia: {
            url: process.env.SEPOLIA_RPC,
            accounts: [process.env.PRIVATEKEY]
        },
        mumbai: {
            url: process.env.MUMBAI_RPC,
            gasPrice: 35000000000,
            accounts: [process.env.PRIVATEKEY]
        },
        hardhat: {
            allowUnlimitedContractSize: true
        },
        dev: {
            url: process.env.DEV_RPC,
            allowUnlimitedContractSize: true,
            accounts: [process.env.PRIVATEKEY]
        },
    },
    etherscan: {
        apiKey: process.env.POLYGONSCAN_API_KEY
    },
}
