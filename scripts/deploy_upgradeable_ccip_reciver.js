// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { network, upgrades } = require("hardhat");

async function main() {
  // Obtain reference to contract and ABI.
  const Receiver = await hre.ethers.getContractFactory("UpgradeableReceiver");
  console.log("Deploying CCIPReceiver to", network.name);
  if (network.name != "mumbai") {
    console.log("Network error");
    return
  }
  const receiver = await upgrades.deployProxy(
    Receiver,
    // _router,_rtoken
    ["0x70499c328e1E2a3c41108bd3730F6670a44595D1", ""],
    { initializer: "initialize" }
  );

  await receiver.waitForDeployment();

  console.log("CCIPReceiver deployed to:", receiver.target);
}

main();