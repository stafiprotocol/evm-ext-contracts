// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { upgrades } = require("hardhat");

async function main() {
  const deployedProxyAddress = "";

  const Sender = await hre.ethers.getContractFactory(
    "UpgradeableSender"
  );
  console.log("Upgrading Sender...");

  await upgrades.upgradeProxy(deployedProxyAddress, Sender);
  console.log("Sender upgraded");
}

main();