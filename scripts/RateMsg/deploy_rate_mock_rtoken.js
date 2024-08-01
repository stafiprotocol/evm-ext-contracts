const hre = require("hardhat");

async function main() {
    console.log("Deploying MockRToken...");

    // Get the ContractFactory and Signer
    const MockRToken = await hre.ethers.getContractFactory("MockRToken");

    // Set the initial rate (adjust as needed)
    const initialRate = hre.ethers.parseUnits("1", 18);  // 1 with 18 decimal places

    // Deploy the contract
    const mockRToken = await MockRToken.deploy(initialRate);

    // Wait for the contract to be deployed
    await mockRToken.waitForDeployment();

    console.log("MockRToken deployed to:", await mockRToken.getAddress());
    console.log("Initial rate set to:", hre.ethers.formatUnits(initialRate, 18));

    // Verify the contract on Etherscan
    if (hre.network.name !== "hardhat" && hre.network.name !== "local") {
        console.log("Verifying contract on Etherscan...");
        await hre.run("verify:verify", {
            address: await mockRToken.getAddress(),
            constructorArguments: [initialRate],
        });
        console.log("Contract verified on Etherscan");
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});