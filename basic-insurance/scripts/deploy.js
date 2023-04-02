// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  console.log(`Deployment has started!`);

//   const UsdcFactory = await hre.ethers.getContractFactory("Usdc");
//   const usdc = await UsdcFactory.deploy();
//   await usdc.deployed();

//   console.log(
//     `Usdc deployed to ${usdc.address}`
//   );
  
//   const usdcAddress = usdc.address;

  const usdcAddress = "0xA024b51C781af21A09D8e3cB324c14287445526B"

  const RainInsuranceFactory = await hre.ethers.getContractFactory("RainInsurance");
  const rainInsurance = await RainInsuranceFactory.deploy(usdcAddress);
  await rainInsurance.deployed();

  console.log(
    `RainInsurance deployed to ${rainInsurance.address}`
  );

//   const funding = hre.ethers.utils.parseUnits("1000000", 6);

//   usdc.transfer(rainInsurance.address, funding);

//   console.log(
//     `${ethers.utils.formatUnits(funding, 6)} USDC funded to ${rainInsurance.address}`
//   );

// npx hardhat run scripts/deploy.js --network polygon_mumbai
// Usdc deployed to 0xA024b51C781af21A09D8e3cB324c14287445526B
// RainInsurance deployed to 0xB5722ad654e72034e939265508A9b3c3c8A6762E

// npx hardhat verify --network polygon_mumbai <usdcAddress>
// https://mumbai.polygonscan.com/address/0xA024b51C781af21A09D8e3cB324c14287445526B#code

// npx hardhat verify --network polygon_mumbai <rainInsuranceAddress> <usdcAddress>
// https://mumbai.polygonscan.com/address/0xB5722ad654e72034e939265508A9b3c3c8A6762E#code
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
