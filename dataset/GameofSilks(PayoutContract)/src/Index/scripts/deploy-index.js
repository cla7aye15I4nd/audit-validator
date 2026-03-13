const path = require("path")
require('dotenv').config({ path: path.join(__dirname, '..', '.env') })

const hre = require("hardhat");

const verifyContract = ({
                            network,
                            name,
                            contractAddress,
                            constructorArguments,
                            contractLocation,
                            verifyWaitTimeInSeconds = 60
                        }) => {
    return new Promise((resolve, reject) => {
        console.log(`[verifyContract] Waiting ${verifyWaitTimeInSeconds} seconds to verify contract ${name}.`)

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
        }, (verifyWaitTimeInSeconds*1000))
    })
}

async function main() {

    const name = "Index";

    const stage = process.env.STAGE;

    const network = hre.network.name;

    const argFileName = `index-arguments-${stage}-${network}`;

    const args = require(`./${argFileName}`);

    // 1. Deploy Contract
    const Index = await hre.ethers.getContractFactory(name);
    const index = await Index.deploy(...args);
    await index.deployed();

    const contractAddress = index.address;

    // const contractAddress = '0xa3E11D6b2B68D73B0d359666F12C54EF933A4c47';
    console.log("Index deployed to:", contractAddress);

    const contractLocation = `../artifacts/contracts/${name}.sol:${name}`
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