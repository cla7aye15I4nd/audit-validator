const path = require("path")
require('dotenv').config({ path: path.join(__dirname, '..', '.env') })

const hre = require("hardhat");

const DIAMOND_INFO = require(`./diamond-info-${hre.network.name}.json`);
const fs = require("fs");
const CONTRACTS = DIAMOND_INFO.facets;
const DIAMOND_NAME = DIAMOND_INFO.diamond.name;

const FacetCutAction = {
    Add: 0,
    Replace: 1,
    Remove: 2
}

const verifyContract = ({
                            network,
                            name,
                            contractAddress,
                            constructorArguments,
                            contractLocation
                        }) => {
    return new Promise((resolve, reject) => {
        const verifyWaitTimeInMs = 1;
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

const getFacets = async () => {

    const facets = [];
    for(let i = 0; i < CONTRACTS.length; i++){
        const contract = CONTRACTS[i];
        console.log(`[main] contract ${contract.name} deploying...`);

        const startTime = new Date().getTime();
        let deployedFacet;
        if (contract.skip){
            deployedFacet = await hre.ethers.getContractAt(contract.name, contract.address);
        } else {
            const contractFactory = await hre.ethers.getContractFactory(contract.name);
            deployedFacet = await contractFactory.deploy([]);
            await deployedFacet.deployed();
        }
        console.log(`[main] contract ${contract.name} deployed to ${deployedFacet.address} (duration: ${new Date().getTime()-startTime} ms)`);
        facets.push({
            name: contract.name,
            deployedFacet,
            upgradeable: contract.upgradeable
        });
    }
    return facets;
}

const getAbi = ({contractName, isFacet = true}) => {
    try {
        const dir = path.resolve(
            __dirname,
            `../artifacts/contracts/${isFacet?'facets/':''}${contractName}.sol/${contractName}.json`
        )
        const file = fs.readFileSync(dir, "utf8")
        const json = JSON.parse(file)
        return json.abi
    } catch (e) {
        console.log(`e`, e)
    }
}

const getFunctionSignature = ({func}) => {
    return `${func.name}(${func.inputs?.length>0?`${func.inputs.map(item=>item.type).join(",")}`:''})`
}

const main = async () => {

    const facets = await getFacets();

    const stage = process.env.STAGE;

    const network = hre.network.name;

    const argFileName = `horse-v2-arguments-${stage}-${network}`;

    const contractOwnerAddress = (await hre.ethers.getSigners())[0].address
    const args = require(`./${argFileName}`);
    const constructorArguments = [contractOwnerAddress, ...args];

    console.log(`[main] Constructor Arguments`, constructorArguments);

    const diamondFactory = await hre.ethers.getContractFactory(DIAMOND_NAME)
    const diamondCut = [];
    const contractSignatures = [];
    const abis = []
    for (let i = 0; i < facets.length; i++) {
        const { name, deployedFacet } = facets[i];
        if (name !== "DiamondCutFacet"){
            console.log(`[main] Facet: ${name} (${deployedFacet.address})`)
            const signaturesToSelectors = Object.keys(deployedFacet.interface.functions).reduce((acc, val) => {
                if (val !== 'init(bytes)' && val !== 'supportsInterface(bytes4)') {
                    acc.push({
                        function: val,
                        selector: deployedFacet.interface.getSighash(val)
                    })
                }
                return acc
            }, [])
            diamondCut.push([
                deployedFacet.address,
                FacetCutAction.Add,
                signaturesToSelectors.map(val => val.selector)
            ])
            contractSignatures.push({
                contractName: name,
                contractAddress: deployedFacet.address,
                signaturesToSelectors
            })
        }
        abis.push(getAbi({contractName: name}));
    }
    abis.push(getAbi({contractName: DIAMOND_NAME, isFacet: false}));
    const contractAbi = abis.flat().reduce((acc, func) => {
        const signature = getFunctionSignature({func});
        if(acc.findIndex(item => getFunctionSignature({func: item}) === signature) === -1){
            acc.push(func);
        }
        return acc;
    }, []);

    // console.log(`[main] diamond cut:`, diamondCut);
    // console.log(`[main] contract signatures:`, JSON.stringify(contractSignatures, null, 4));

    const duplicateFunctions = []
    for(let i = 0; i < contractSignatures.length; i++){
        const contractSignature = contractSignatures[i];
        const currentSelectors = contractSignature.signaturesToSelectors;
        for(let j = 0; j < currentSelectors.length; j++){
            const currentSelector = currentSelectors[j].selector;
            // console.log(`[main] currentSelector: ${currentSelector}`);
            for (let k = 0; k < contractSignatures.length; k++){
                if (k !== i){
                    const testContractSignature = contractSignatures[k];
                    const testSelectors = testContractSignature.signaturesToSelectors;
                    for(let l = 0; l < testSelectors.length; l++){
                        const testSelector = testSelectors[l].selector;
                        // console.log(`            testSelector: ${testSelector}`);
                        if (testSelector === currentSelector){
                            if (duplicateFunctions.findIndex(val => val.selector === testSelector) === -1){
                                duplicateFunctions.push({
                                    contract1: contractSignature.contractName,
                                    contract2: testContractSignature.contractName,
                                    function: testSelectors[l].function,
                                    selector: testSelector,
                                })
                            }
                        }
                    }
                }
            }
        }
    }

    if (duplicateFunctions.length > 0){
        console.log(`[main] duplicate functions found:`, duplicateFunctions);
        return;
    }

    let diamondAddress = DIAMOND_INFO.diamond.address;

    if (!diamondAddress || diamondAddress.length === 0){
        console.log(`[main] ${DIAMOND_NAME} constructor arguments:`, constructorArguments)

        const deployedDiamond = await diamondFactory.deploy(...constructorArguments);
        await deployedDiamond.deployed()
        console.log('[main] Transaction hash: ' + deployedDiamond.deployTransaction.hash)
        diamondAddress = deployedDiamond.address;
    }

    for (let i = 0; i < facets.length; i++){
        const { name, deployedFacet } = facets[i];
        const contractLocation = `../artifacts/contracts/facets/${name}.sol:${name}`
        await verifyContract({
            network, name, contractAddress: deployedFacet.address, contractLocation
        })
    }

    await verifyContract({
        network, name: DIAMOND_NAME, constructorArguments, contractAddress: diamondAddress,
        contractLocation: `../artifacts/contracts/${DIAMOND_NAME}.sol:${DIAMOND_NAME}`
    })

    console.log(`[main] ${DIAMOND_NAME} deployed to: ${diamondAddress}`);

    const horseContract = await hre.ethers.getContractAt(contractAbi, diamondAddress);
    // console.log({horseContract});
    const initFacet = facets.find((facet) => facet.name.indexOf("DiamondInit") > -1 ).deployedFacet;
    const callData = (new hre.ethers.utils.Interface(["function init() external"])).encodeFunctionData("init");

    // console.log(`[main] init facet address:`, initFacet.address);
    // console.log(`[main] diamond cut:`, diamondCut);
    // console.log(`[main] callData:`, callData);
    const diamondCutTx = await horseContract.diamondCut(diamondCut, initFacet.address, callData);
    await diamondCutTx.wait();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
