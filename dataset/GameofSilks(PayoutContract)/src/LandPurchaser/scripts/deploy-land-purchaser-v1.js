const path = require("path")
require('dotenv').config({ path: path.join(__dirname, '..', '.env') })

const hre = require("hardhat");

const verifyContract = ({
                            network,
                            name,
                            contractAddress,
                            constructorArguments,
                            contractLocation,
                            verifyWaitTimeInMs = 60
                        }) => {
    return new Promise((resolve, reject) => {
        console.log(`[verifyContract] Waiting ${verifyWaitTimeInMs} seconds to verify contract ${name}.`)

        setTimeout(async () => {
            try {
                console.log(`[verifyContract] Attempting to verify contract at address ${contractAddress}`);
                const taskArguments = {
                    address: contractAddress,
                    // contract: contractLocation
                }

                if (constructorArguments){
                    taskArguments["constructorArguments"] = constructorArguments;
                }
                // console.log(`[verifyContract: ${JSON.stringify(taskArguments)}`);
                await hre.run(`verify:verify`, taskArguments);
            } catch (error){
                if (error.message.includes("Reason: Already Verified")) {
                    console.log("[verifyContract] Contract is already verified!");
                } else {
                    console.error(error);
                    console.log(`
[verifyContract] Error verifying contract. You man have to do it manually.

[verifyContract] Verify the contract by running the following command:
[verifyContract] npx hardhat verify --contract ${contractLocation.replace("../", "")} --network ${network} ${contractAddress} ${constructorArguments? JSON.stringify(constructorArguments) : ''}
                        `)
                }
            }

            resolve();
        }, (verifyWaitTimeInMs*1000))
    })
}

async function main() {

    const name = "LandPurchaserV1";

    const stage = process.env.STAGE;

    const network = hre.network.name;

    const argFileName = `land-purchaser-arguments-${stage}-${network}`;

    const args = require(`./${argFileName}`);

    // 1. Deploy Contract
    const LandPurchaser = await hre.ethers.getContractFactory(name);
    const landPurchaser = await LandPurchaser.deploy(...args);
    await landPurchaser.deployed();

    const contractAddress = landPurchaser.address;

    console.log("LandPurchaser deployed to:", contractAddress);

    const contractLocation = `../artifacts/contracts/facets/${name}.sol:${name}`
    await verifyContract({
        network, name, contractAddress: contractAddress, contractLocation, constructorArguments: args
    })
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

// const network = 'goerli';
// const name = "LandPurchaserV1";
// const contractAddress = "0x5508E61E30F19F96238f70EF51509189B7b74c4d";
// const contractLocation = "../artifacts/contracts/facets/LandPurchaserV1.sol:LandPurchaserV1"
// const args = require(`./land-purchaser-arguments-dev-goerli`);
//
// verifyContract({
//     network, name, contractAddress: contractAddress, contractLocation, constructorArguments: args, verifyWaitTimeInMs: 2
// }).catch((error => console.error(error)))