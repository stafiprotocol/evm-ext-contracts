// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { network, upgrades } = require("hardhat");

async function main() {

  if (network.name != "sepolia") {
    console.log("Network error");
    return
  }

  const deployedProxyAddress = "";

  const Automation = await hre.ethers.getContractFactory(
    "RateSyncAutomation"
  );

  console.log("Upgrading RateSyncAutomation...");

  await upgrades.upgradeProxy(deployedProxyAddress, Automation);
  console.log("RateSyncAutomation upgraded");
}

main();