// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { upgrades } = require("hardhat");

async function main() {
  const deployedProxyAddress = "";

  const Receiver = await hre.ethers.getContractFactory(
    "UpgradeableReceiver"
  );

  console.log("Upgrading UpgradeableReceiver...");

  await upgrades.upgradeProxy(deployedProxyAddress, Receiver);
  console.log("UpgradeableReceiver upgraded");
}

main();