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

async function deployMockRToken(deployer, name, initialRate) {
  console.error(`Deploying MockRToken for ${name}...`);
  const MockRToken = await hre.ethers.getContractFactory("MockRToken", deployer);
  const mockRToken = await MockRToken.deploy(hre.ethers.parseUnits(initialRate, 18));
  await mockRToken.waitForDeployment();
  const deployedAddress = await mockRToken.getAddress();

  // Verify the contract on Etherscan
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.error(`Verifying MockRToken for ${name} on Etherscan...`);
    await hre.run("verify:verify", {
      address: deployedAddress,
      constructorArguments: [hre.ethers.parseUnits(initialRate, 18)],
    });
    console.error(`MockRToken for ${name} verified on Etherscan`);
  }

  return deployedAddress;
}

async function deployRateSender(deployer, routerAddress, linkAddress) {
  console.log("Deploying RateSender...");
  console.log(`Router address: ${routerAddress}`);
  console.log(`Link address: ${linkAddress}`);

  if (!routerAddress || !hre.ethers.isAddress(routerAddress)) {
    throw new Error(`Invalid router address: ${routerAddress}`);
  }
  if (!linkAddress || !hre.ethers.isAddress(linkAddress)) {
    throw new Error(`Invalid link address: ${linkAddress}`);
  }

  const RateSender = await hre.ethers.getContractFactory("RateSender", deployer);
  const adminAddress =  deployer.address;

  console.log("Deploying RateSender contract...");
  const rateSender = await hre.upgrades.deployProxy(RateSender, [routerAddress, linkAddress, adminAddress], { initializer: 'initialize' });

  console.log("Waiting for RateSender deployment...");
  await rateSender.waitForDeployment();

  const deployedAddress = await rateSender.getAddress();
  console.log(`RateSender deployed at ${deployedAddress}`);

  return deployedAddress;
}

function getRateSourceTypeEnum(rateSourceType) {
  switch (rateSourceType.toUpperCase()) {
    case 'RATE':
      return 0;
    case 'EXCHANGE_RATE':
      return 1;
    default:
      throw new Error(`Invalid RateSourceType: ${rateSourceType}`);
  }
}

async function main() {
  console.log("Starting main deployment process");
  const deployer = (await hre.ethers.getSigners())[0];
  console.log(`Deployer address: ${deployer.address}`);

  const deployedRTokens = {};
  for (const rtoken of config.rtokens) {
    console.log(`Processing rtoken: ${rtoken.name}`);
    if (!rtoken.address) {
      deployedRTokens[rtoken.name] = await deployMockRToken(deployer, rtoken.name, rtoken.initialRate);
    } else {
      deployedRTokens[rtoken.name] = rtoken.address;
    }
    console.log(`RToken ${rtoken.name} address: ${deployedRTokens[rtoken.name]}`);
  }

  console.log("Deploying RateSender...");
  let rateSenderAddress;
  try {
    rateSenderAddress = await deployRateSender(deployer, config.routerAddressSource, config.linkAddressSource);
    console.log(`RateSender deployed at ${rateSenderAddress}`);
  } catch (error) {
    console.error("Error deploying RateSender:", error);
    process.exit(1);
  }

  // Add RTokens to RateSender
  console.log("Adding RTokens to RateSender...");
  const RateSender = await hre.ethers.getContractFactory("RateSender", deployer);
  const rateSender = await RateSender.attach(rateSenderAddress);

  for (const rtoken of config.rtokens) {
    console.log(`Adding ${rtoken.name} to RateSender...`);
    try {
      await rateSender.addRTokenInfo(
        rtoken.name,
        deployedRTokens[rtoken.name],
        getRateSourceTypeEnum(rtoken.rateSourceType),
        rtoken.destination.receiver,
        rtoken.destination.rateProvider,
        rtoken.destination.selector
      );
      console.log(`${rtoken.name} added to RateSender`);
    } catch (error) {
      console.error(`Error adding ${rtoken.name} to RateSender:`, error);
    }
  }

  const result = {
    rateSenderAddress,
    deployedRTokens
  };

  // Log detailed results to stderr for human reading
  console.error("Deployment complete. Detailed Result:");
  console.error(JSON.stringify(result, null, 2));

  // Output only the necessary JSON to stdout for shell script parsing
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