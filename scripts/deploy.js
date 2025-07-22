const hre = require("hardhat");

async function main() {
  // Get the contract factory for EscrowX
  const EscrowX = await hre.ethers.getContractFactory("EscrowX");

  // Deploy the contract
  const escrowX = await EscrowX.deploy();

  // Wait for the contract to be deployed
  await escrowX.deployed();

  console.log("EscrowX contract deployed to:", escrowX.address);
}

// Recommended pattern to handle errors
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
