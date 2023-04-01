// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  const UsdcFactory = await hre.ethers.getContractFactory("Usdc");
  const usdc = await UsdcFactory.deploy();
  await usdc.deployed();

  console.log(
    `Usdc deployed to ${usdc.address}`
  );
  
  const RainInsuranceFactory = await hre.ethers.getContractFactory("RainInsurance");
  const rainInsurance = await RainInsuranceFactory.deploy(usdc.address);
  await rainInsurance.deployed();

  console.log(
    `RainInsurance deployed to ${rainInsurance.address}`
  );

  const funding = hre.ethers.utils.parseUnits("1000000", 6);

  usdc.transfer(rainInsurance.address, funding);

  console.log(
    `${ethers.utils.formatUnits(funding, 6)} USDC funded to ${rainInsurance.address}`
  );

//   Usdc deployed to 0x8873a4e84C0AD3FD56eBcbA4FB19f13fDe1586BC
//   RainInsurance deployed to 0x2bcA53f3EeB12B758A0D241a213C6107224549bA
//   1000000.0 USDC funded to 0x2bcA53f3EeB12B758A0D241a213C6107224549bA

// https://mumbai.polygonscan.com/address/0x8873a4e84C0AD3FD56eBcbA4FB19f13fDe1586BC#code
// https://mumbai.polygonscan.com/address/0x2bcA53f3EeB12B758A0D241a213C6107224549bA#code
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
