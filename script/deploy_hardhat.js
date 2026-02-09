#!/usr/bin/env node
/* eslint-disable no-console */
const hre = require('hardhat');

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log('Deploying with', deployer.address);

    const AdapterRegistry = await hre.ethers.getContractFactory('AdapterRegistry');
    const FlashLoanRouter = await hre.ethers.getContractFactory('FlashLoanRouter');
    const UniversalSwapRouter = await hre.ethers.getContractFactory('UniversalSwapRouter');
    const Liiquidate = await hre.ethers.getContractFactory('Liiquidate');

    const adapterRegistry = await AdapterRegistry.deploy();
    await adapterRegistry.deployed();

    const flashLoanRouter = await FlashLoanRouter.deploy();
    await flashLoanRouter.deployed();

    const swapRouter = await UniversalSwapRouter.deploy();
    await swapRouter.deployed();

    const liiquidate = await Liiquidate.deploy(
        hre.ethers.constants.AddressZero,
        hre.ethers.constants.AddressZero,
        flashLoanRouter.address
    );
    await liiquidate.deployed();

    console.log('AdapterRegistry:', adapterRegistry.address);
    console.log('FlashLoanRouter:', flashLoanRouter.address);
    console.log('UniversalSwapRouter:', swapRouter.address);
    console.log('Liiquidate:', liiquidate.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
