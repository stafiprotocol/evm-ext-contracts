require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();
require("hardhat-gas-reporter");
require('solidity-coverage')

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
