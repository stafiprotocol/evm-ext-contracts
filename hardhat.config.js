require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
require("@openzeppelin/hardhat-upgrades");
require('dotenv').config();
require("hardhat-gas-reporter");
require('solidity-coverage')

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        version: "0.8.24",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: false,
        },
    },
    contractSizer: {
        alphaSort: true,
        runOnCompile: false,
        disambiguatePaths: false,
    },
    etherscan: {
        apiKey: {
            avalancheFujiTestnet: "snowtrace",
        }
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
        },
        local: {
            allowUnlimitedContractSize: true,
            url: "http://127.0.0.1:8545/"
        },
        fuji: {
            url: process.env.AVALANCHE_FUJI_RPC,
            accounts: [process.env.PRIVATEKEY]
        },
    }
}
