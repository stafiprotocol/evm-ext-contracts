// The Open Zeppelin upgrades plugin adds the `upgrades` property
// to the Hardhat Runtime Environment.
const { network, upgrades } = require("hardhat");

async function main() {
  // Obtain reference to contract and ABI.
  const RateSync = await hre.ethers.getContractFactory("RateSyncAutomation");
  console.log("Deploying RateSync to", network.name);
  if (network.name != "sepolia") {
    console.log("Network error");
    return
  }

  const sender = await upgrades.deployProxy(
    RateSync,
    // ccip register , sender
    ["0xE16Df59B887e3Caa439E0b29B42bA2e7976FD8b2", ""],
    { initializer: "initialize" }
  );

  await sender.waitForDeployment();

  console.log("RateSync deployed to:", sender.target);
}

main();