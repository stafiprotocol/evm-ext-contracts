const hre = require("hardhat");
const fs = require('fs');
const path = require('path');

// Load configuration
let config;
try {
  config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
  console.error("Config loaded:", config);
} catch (error) {
  console.error("Error loading config:", error);
  process.exit(1);
}

async function deployMockRToken(deployer) {
  console.error(`Deploying MockRToken...`);
  const MockRToken = await hre.ethers.getContractFactory("MockRToken", deployer);
  const initialRate = hre.ethers.parseUnits(config.initialRate || "1", 18);
  const mockRToken = await MockRToken.deploy(initialRate);
  await mockRToken.waitForDeployment();
  const deployedAddress = await mockRToken.getAddress();

  // Verify the contract on Etherscan
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.error("Verifying MockRToken on Etherscan...");
    await hre.run("verify:verify", {
      address: deployedAddress,
      constructorArguments: [initialRate],
    });
    console.error("MockRToken verified on Etherscan");
  }

  return deployedAddress;
}

async function deployRateSender(deployer, routerAddress, linkAddress) {
  console.error(`Deploying RateSender...`);
  console.error(`Router address: ${routerAddress}`);
  console.error(`Link address: ${linkAddress}`);

  if (!routerAddress || !hre.ethers.isAddress(routerAddress)) {
    throw new Error(`Invalid router address: ${routerAddress}`);
  }
  if (!linkAddress || !hre.ethers.isAddress(linkAddress)) {
    throw new Error(`Invalid link address: ${linkAddress}`);
  }

  const RateSender = await hre.ethers.getContractFactory("RateSender", deployer);
  const adminAddress = config.adminAddress || deployer.address;
  const rateSender = await hre.upgrades.deployProxy(RateSender, [routerAddress, linkAddress, adminAddress], {initializer: 'initialize'});
  await rateSender.waitForDeployment();
  const deployedAddress = await rateSender.getAddress();

  // Verify the contract on Etherscan
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.error("Verifying RateSender on Etherscan...");
    await hre.run("verify:verify", {
      address: deployedAddress,
      constructorArguments: [],
    });
    console.error("RateSender verified on Etherscan");
  }

  return deployedAddress;
}

async function main() {
  const deployer = (await hre.ethers.getSigners())[0];

  const mockRTokenAddress = await deployMockRToken(deployer);
  const rateSenderAddress = await deployRateSender(deployer, config.routerAddressSource, config.linkAddressSource);

  const result = {
    mockRTokenAddress,
    rateSenderAddress
  };

  console.log(JSON.stringify(result));
  return result;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { main };