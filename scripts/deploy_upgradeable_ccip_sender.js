// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { network, upgrades } = require("hardhat");

async function main() {
  // Obtain reference to contract and ABI.
  const Sender = await hre.ethers.getContractFactory("UpgradeableSender");
  console.log("Deploying UpgradeableSender to", network.name);
  if (network.name != "sepolia") {
    console.log("Network error");
    return
  }
  const sender = await upgrades.deployProxy(
    Sender,
    // _router,_link
    ["0xD0daae2231E9CB96b94C8512223533293C3693Bf", "0x779877A7B0D9E8603169DdbD7836e478b4624789"],
    { initializer: "initialize" }
  );

  await sender.waitForDeployment();

  console.log("UpgradeableSender deployed to:", sender.target);
}

main();