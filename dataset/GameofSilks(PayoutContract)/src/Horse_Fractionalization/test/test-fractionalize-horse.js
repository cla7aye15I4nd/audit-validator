const {expect} = require("chai");
const hre = require("hardhat");
const fs = require("fs")
const path = require("path")

const DIAMOND_INFO = require("../scripts/diamond-info-goerli.json");

const getAbi = ({contractName, folder = ""}) => {
    try {
        const dir = path.resolve(
            __dirname,
            `../artifacts/contracts/${folder}${contractName}.sol/${contractName}.json`
        )
        const file = fs.readFileSync(dir, "utf8")
        // console.log(file)
        const json = JSON.parse(file)
        return json.abi
    } catch (e) {
        console.log(`e`, e)
    }
}

const getFunctionSignature = ({func}) => {
    return `${func.name}(${func.inputs?.length>0?`${func.inputs.map(item=>item.type).join(",")}`:''})`
}

const getSignatures = async ({deployedFacet} = {}) => {
    return Object.keys(deployedFacet.interface.functions).reduce((acc, val) => {
        if (val !== 'init(bytes)' && val !== 'supportsInterface(bytes4)') {
            acc.push({
                function: val,
                selector: deployedFacet.interface.getSighash(val)
            })
        }
        return acc
    }, [])
}

describe("Horse Partnership Test Cases", function () {

    let marketPlaceDummyContract;
    let hardHatMarketPlaceDummy;

    let horseDummyContract;
    let hardHatHorseDummy;

    let indexContract;
    let hardHatIndex;

    let horseFractionalizationContract;
    let hardHatHorseFractionalization;

    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addr4
    let addrs;

    const horses = {};
    let horseId;

    let horsePartnershipContractAddress;

    // const horsePartnershipFacets = {};

    let DEFAULT_ADMIN_ROLE;
    let CONTRACT_ADMIN_ROLE;
    let CONFIG_ADMIN_ROLE;
    let FRACTIONALIZATION_ADMIN_ROLE;
    let RECONSTITUTION_ADMIN_ROLE;
    let BURNER_ROLE;

    const fractionalizeHorse = async ({connectAs = addr1, id = horseId} = {}) => {
        await hardHatHorseFractionalization.connect(connectAs).fractionalize(id);
    }
    const transferShares = async ({num = 1,
                                      from = addr1,
                                      to = addr3,
                                      id = horseId} = {}) => {
        await hardHatHorseFractionalization.connect(from)
            .safeTransferFrom(from.address, to.address, id, num, "0x");
    }

    const mintHorses = async () => {
        await hardHatHorseDummy.connect(addr1).publicMint(4);
        horses[addr1.address] = [
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 0)).toNumber(),
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 1)).toNumber(),
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 2)).toNumber(),
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 3)).toNumber(),
        ]

        await hardHatHorseDummy.connect(addr2).publicMint(2);
        horses[addr2.address] = [
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr2.address, 0)).toNumber(),
            (await hardHatHorseDummy.tokenOfOwnerByIndex(addr2.address, 1)).toNumber(),
        ]

        // console.log({horses});

        await hardHatHorseFractionalization.unpause();

        horseId = horses[addr1.address][0];
    }

    beforeEach(async function () {
        [owner, addr1, addr2, addr3, addr4, ...addrs] = await hre.ethers.getSigners();

        horseDummyContract = await hre.ethers.getContractFactory("HorseDummy");
        hardHatHorseDummy = await horseDummyContract.deploy();
        const horseDummyAddress = hardHatHorseDummy.address;

        marketPlaceDummyContract = await hre.ethers.getContractFactory("MarketPlaceDummy");
        hardHatMarketPlaceDummy = await marketPlaceDummyContract.deploy();
        const marketPlaceDummyAddress = hardHatMarketPlaceDummy.address;

        const indexContractArguments = [
            ["Horse", "Marketplace"],
            [horseDummyAddress, marketPlaceDummyAddress]
        ];

        indexContract = await hre.ethers.getContractFactory("Index");
        hardHatIndex = await indexContract.deploy(...indexContractArguments);
        const indexAddress = hardHatIndex.address;

        const diamondName = DIAMOND_INFO.diamond.name;
        const diamondFacets = DIAMOND_INFO.facets;

        const facets = [];
        for(let i = 0; i < diamondFacets.length; i++){
            const facet = diamondFacets[i];
            const contractFactory = await hre.ethers.getContractFactory(facet.name);
            const deployedFacet = await contractFactory.deploy([]);
            facets.push({
                name: facet.name,
                deployedFacet,
                upgradeable: facet.upgradeable
            })
        }

        const diamondCut = [];
        const contractSignatures = [];
        const abis = [];
        for(let i = 0; i < facets.length; i++){
            // console.log({facet: facets[i]})
            const { name, deployedFacet } = facets[i];
            if (name !== "DiamondCutFacet"){
                // console.log(`[main] Facet: ${name} (${deployedFacet.address})`)
                const signaturesToSelectors = await getSignatures({deployedFacet});
                diamondCut.push([
                    deployedFacet.address,
                    0,
                    signaturesToSelectors.map(val => val.selector)
                ])
                contractSignatures.push({
                    contractName: name,
                    contractAddress: deployedFacet.address,
                    signaturesToSelectors
                })
            }
            abis.push(getAbi({contractName: name, folder: "facets/"}));
        }
        abis.push(getAbi({contractName: diamondName}));
        const contractAbi = abis.flat().reduce((acc, func) => {
            const signature = getFunctionSignature({func});
            if(acc.findIndex(item => getFunctionSignature({func: item}) === signature) === -1){
                acc.push(func);
            }
            return acc;
        }, []);

        // console.log(JSON.stringify(contractAbi))

        // console.log(`[main] diamond cut:`, diamondCut);
        // console.log(`[main] contract signatures:`, JSON.stringify(contractSignatures, null, 4));

        const duplicateFunctions = [];
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
            throw new Error("duplicate functions found");
        }

        const diamondCutFacetAddress = facets.find((facet) => facet.name === "DiamondCutFacet").deployedFacet.address;

        // console.log(`[beforeEach] diamond cut address: ${diamondCutFacetAddress}`);
        const horseFractionalizationArguments = [
            owner.address,
            diamondCutFacetAddress,
            "https://nft.dev.silks.io/metadata/HorsePartnership/",
            indexAddress,
            owner.address,
            8
        ]

        // console.log({
        //     diamondName, horseFractionalizationArguments
        // })

        horseFractionalizationContract = await hre.ethers.getContractFactory(diamondName);
        hardHatHorseFractionalization = await horseFractionalizationContract.deploy(...horseFractionalizationArguments);
        await hardHatHorseFractionalization.deployed();

        horsePartnershipContractAddress = hardHatHorseFractionalization.address;

        hardHatHorseFractionalization = await hre.ethers.getContractAt(contractAbi, horsePartnershipContractAddress);

        const initFacet = facets.find((facet) => facet.name === "DiamondInit").deployedFacet;
        const callData = (new hre.ethers.utils.Interface(["function init() external"])).encodeFunctionData("init");

        const diamondCutTx = await hardHatHorseFractionalization.diamondCut(diamondCut, initFacet.address, callData);
        await diamondCutTx.wait();

        DEFAULT_ADMIN_ROLE = await hardHatHorseFractionalization.DEFAULT_ADMIN_ROLE()
        CONTRACT_ADMIN_ROLE = await hardHatHorseFractionalization.CONTRACT_ADMIN_ROLE()
        CONFIG_ADMIN_ROLE = await hardHatHorseFractionalization.CONFIG_ADMIN_ROLE();
        FRACTIONALIZATION_ADMIN_ROLE = await hardHatHorseFractionalization.FRACTIONALIZATION_ADMIN_ROLE();
        RECONSTITUTION_ADMIN_ROLE = await hardHatHorseFractionalization.RECONSTITUTION_ADMIN_ROLE();
        BURNER_ROLE = await hardHatHorseFractionalization.BURNER_ROLE();

        // console.log({CONTRACT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE, FRACTIONALIZATION_ADMIN_ROLE, RECONSTITUTION_ADMIN_ROLE, BURNER_ROLE, CONFIG_ADMIN_ROLE});
    });

    describe("Admin functions", function () {
        describe("Pause contract", function () {
            beforeEach(async function() {
                await hardHatHorseFractionalization.unpause();
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.pause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.true;
            });
            it("Executed by contract admin", async function () {
                await hardHatHorseFractionalization.grantRole(CONTRACT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).pause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.true;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).pause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.true;
            });
            it("Executed by non contract owner or admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).pause()).to.be.reverted;
            });
        })
        describe("Unpause contract", function () {
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.unpause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.false;
            });
            it("Executed by contract admin", async function () {
                await hardHatHorseFractionalization.grantRole(CONTRACT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).unpause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.false;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).unpause();
                expect(
                    await hardHatHorseFractionalization.paused()
                ).to.be.false;
            });
            it("Executed by non contract owner (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).unpause()).to.be.reverted;
            });
        })
        describe("Pause fractionalization", function() {
            beforeEach(async function() {
                await hardHatHorseFractionalization.grantRole(FRACTIONALIZATION_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.pauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.true;
            });
            it("Executed by fractionalization admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).pauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.true;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).pauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.true;
            });
            it("Executed by non fractionalization admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).pauseFractionalization()).to.be.reverted;
            });
        });
        describe("Unpause fractionalization", function() {
            beforeEach(async function() {
                await hardHatHorseFractionalization.pauseFractionalization();
                await hardHatHorseFractionalization.grantRole(FRACTIONALIZATION_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.unPauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.false;
            });
            it("Executed by fractionalization admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).unPauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.false;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).unPauseFractionalization();
                expect(
                    await hardHatHorseFractionalization.fractionalizationPaused()
                ).to.be.false;
            });
            it("Executed by non fractionalization admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).unPauseFractionalization()).to.be.reverted;
            });
        });
        describe("Pause reconstitution", function() {
            beforeEach(async function() {
                await hardHatHorseFractionalization.grantRole(RECONSTITUTION_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.pauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.true;
            });
            it("Executed by reconstitution admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).pauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.true;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).pauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.true;
            });
            it("Executed by non reconstitution admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).pauseReconstitution()).to.be.reverted;
            });
        });
        describe("Unpause reconstitution", function() {
            beforeEach(async function() {
                await hardHatHorseFractionalization.pauseReconstitution();
                await hardHatHorseFractionalization.grantRole(RECONSTITUTION_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.unPauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.false;
            });
            it("Executed by reconstitution admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).unPauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.false;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).unPauseReconstitution();
                expect(
                    await hardHatHorseFractionalization.reconstitutionPaused()
                ).to.be.false;
            });
            it("Executed by non reconstitution admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).unPauseReconstitution()).to.be.reverted;
            });
        })
        describe("Update max number of shares", function () {
            const testValue = 20;
            beforeEach(async function(){
                await hardHatHorseFractionalization.grantRole(CONFIG_ADMIN_ROLE, addr3.address);
            });
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.setMaxPartnershipShares(testValue);
                expect(
                    await hardHatHorseFractionalization.maxPartnershipShares()
                ).to.be.equal(testValue);
            });
            it("Executed by configuration admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).setMaxPartnershipShares(testValue);
                expect(
                    await hardHatHorseFractionalization.maxPartnershipShares()
                ).to.be.equal(testValue);
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).setMaxPartnershipShares(testValue);
                expect(
                    await hardHatHorseFractionalization.maxPartnershipShares()
                ).to.be.equal(testValue);
            });
            it("Executed by non configuration admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).setMaxPartnershipShares(20)).to.be.reverted;
            });
        })
        describe("Update metadata uri", function () {
            const testValue = "https://portal.silks.io/api/HorseFracEqu/HorseFracEqu/";
            const testTokenId = 1;
            beforeEach(async function () {
                await hardHatHorseFractionalization.grantRole(CONFIG_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.setURI(testValue);
                expect(
                    await hardHatHorseFractionalization.uri(testTokenId)
                ).to.be.equal(`${testValue}${testTokenId}`);
            });
            it("Executed by configuration admin", async function () {
                await hardHatHorseFractionalization.connect(addr3).setURI(testValue);
                expect(
                    await hardHatHorseFractionalization.uri(testTokenId)
                ).to.be.equal(`${testValue}${testTokenId}`);
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await hardHatHorseFractionalization.connect(addr1).setURI(testValue);
                expect(
                    await hardHatHorseFractionalization.uri(testTokenId)
                ).to.be.equal(`${testValue}${testTokenId}`);
            });
            it("Executed by non configuration admin (Reverted)", async function () {
                await expect(hardHatHorseFractionalization.connect(addr1).setURI(testValue)).to.be.reverted;
            });
        })
        describe("Update index contract address", function () {
            let hardHatIndex2;

            beforeEach(async function () {
                const indexContract2 = await hre.ethers.getContractFactory("Index");
                hardHatIndex2 = await indexContract2.deploy(
                    ["Horse", "Marketplace"],
                    [hardHatHorseDummy.address, hardHatMarketPlaceDummy.address]
                );
                await hardHatHorseFractionalization.grantRole(CONFIG_ADMIN_ROLE, addr3.address);
            });
            it("Executed by contract owner", async function () {
                await expect(
                    hardHatHorseFractionalization.setContractGlossary(hardHatIndex2.address)
                ).not.to.be.reverted;
            });
            it("Executed as configuration admin", async function () {
                await expect(
                    hardHatHorseFractionalization.connect(addr3).setContractGlossary(hardHatIndex2.address)
                ).not.to.be.reverted;
            });
            it("Executed by default admin", async function () {
                await hardHatHorseFractionalization.grantRole(DEFAULT_ADMIN_ROLE, addr1.address);
                await expect(
                    hardHatHorseFractionalization.connect(addr1).setContractGlossary(hardHatIndex2.address)
                ).not.to.be.reverted;
            });
            it("Executed by non configuration admin (Reverted)", async function () {
                const indexContract3 = await hre.ethers.getContractFactory("Index");
                const hardHatIndex3 = await indexContract3.deploy(
                    ["Horse", "Marketplace"],
                    [hardHatHorseDummy.address, hardHatMarketPlaceDummy.address]
                );
                await expect(hardHatHorseFractionalization.connect(addr1).setContractGlossary(hardHatIndex3.address)).to.be.reverted;
            });
        })
        describe("Grant admin role", function () {
            it("Executed by non contract owner (Reverted)", async function () {
                await expect(
                    hardHatHorseFractionalization.connect(addr1).grantRole(CONFIG_ADMIN_ROLE, addr1.address)
                ).to.be.reverted;
            });
        })
        describe("Revoke admin role", function () {
            beforeEach(async function() {
                await hardHatHorseFractionalization.grantRole(CONFIG_ADMIN_ROLE, addr3.address);
            })
            it("Executed by contract owner", async function () {
                await hardHatHorseFractionalization.revokeRole(CONFIG_ADMIN_ROLE, addr3.address);
                expect(
                    await hardHatHorseFractionalization.hasRole(CONFIG_ADMIN_ROLE, addr3.address)
                ).to.be.false;
            })
            it("Executed by non contract owner (Reverted)", async function () {
                await expect(
                    hardHatHorseFractionalization.connect(addr1).revokeRole(CONFIG_ADMIN_ROLE, addr3.address)
                ).to.be.reverted;
            })
        })
    })

    describe("Diamond Add/Upgrade/Remove", function() {

        let diamond;
        const horses = {};
        let testFacet;

        const testPreviousFacetExists = async () => {
            const horseId = horses[addr1.address][0];
            // console.log({horseId, addr: addr1.address})
            await hardHatHorseFractionalization.connect(addr1).fractionalize(horseId);
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.true;
        }

        beforeEach(async function() {
            await hardHatHorseDummy.connect(addr1).publicMint(4);
            horses[addr1.address] = [
                (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 0)).toNumber(),
            ]

            // console.log({horses});

            await hardHatHorseFractionalization.unpause();

            const contractFactory = await hre.ethers.getContractFactory("TestFacetV1");
            testFacet = await contractFactory.deploy([]);
            const diamondCut = [];
            const signaturesToSelectors = await getSignatures({deployedFacet: testFacet});
            diamondCut.push([
                testFacet.address,
                0,
                signaturesToSelectors.map(val => val.selector)
            ])

            const diamondCutTx = await hardHatHorseFractionalization.diamondCut(diamondCut, hre.ethers.constants.AddressZero, "0x");
            await diamondCutTx.wait();

            diamond = await hre.ethers.getContractAt("TestFacetV1", horsePartnershipContractAddress);
        });

        describe("Add", function() {
            it("Add facet", async function () {
                expect((await diamond.getMessage())).to.be.equal("V1");
            });
            it("Previous function still exist after adding facet", async function () {
                await testPreviousFacetExists();
            })
        })

        describe("Replace", function() {
            beforeEach(async function(){
                const contractFactory = await hre.ethers.getContractFactory("TestFacetV2");
                const deployedFacet = await contractFactory.deploy([]);
                const diamondCut = [];
                const signaturesToSelectors = await getSignatures({deployedFacet});

                diamondCut.push([
                    deployedFacet.address,
                    1,
                    signaturesToSelectors.map(val => val.selector)
                ]);

                const diamondCutTx = await hardHatHorseFractionalization.diamondCut(diamondCut, hre.ethers.constants.AddressZero, "0x");
                await diamondCutTx.wait();
            })
            it("Replace facet", async function () {
                expect((await diamond.getMessage())).to.be.equal("V2");
            });
            it("Previous function still exist after replacing facet", async function () {
                await testPreviousFacetExists();
            })
        })

        describe("Remove", function() {
            beforeEach(async function(){
                const diamondCut = [];
                const signaturesToSelectors = await getSignatures({deployedFacet: testFacet});
                diamondCut.push([
                    hre.ethers.constants.AddressZero,
                    2,
                    signaturesToSelectors.map(val => val.selector)
                ])
                await hardHatHorseFractionalization.diamondCut(diamondCut, hre.ethers.constants.AddressZero, "0x");
            });
            it("Remove facet", async function () {
                await expect(diamond.getMessage()).to.revertedWith("Diamond: Function does not exist");
            });
            it("Previous function still exist after removing facet", async function () {
                await testPreviousFacetExists();
            })
        })
    })

    describe("Fractionalization", function () {

        beforeEach(async function () {
            await mintHorses();
        });

        it("Fractionalize horse (Horse Owner)", async function () {
            await fractionalizeHorse();
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.true;
        });
        it("Fractionalize Horse (Fractionalization Admin)", async function () {
            await hardHatHorseFractionalization.grantRole(FRACTIONALIZATION_ADMIN_ROLE, addr3.address);
            const horseId2 = horses[addr1.address][1];
            // console.log({horseId, addr: addr1.address})
            await hardHatHorseFractionalization.connect(addr3).adminFractionalize([addr1.address], [horseId]);
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.true;
        });

        it("Partnership count is 1 after fractionalization", async function () {
            await fractionalizeHorse();
            expect(
                await hardHatHorseFractionalization.partnershipCount()
            ).to.be.equal(1);
        });
        it("Horse owner has 9 shares after fractionalization", async function () {
            await fractionalizeHorse();
            expect(
                (await hardHatHorseFractionalization.balanceOf(addr1.address, horseId)).toNumber()
            ).to.be.equal(9);
        });
        it("Verify balance of horse shares is 1 after transfer to non partner", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            expect(
                (await hardHatHorseFractionalization.balanceOf(addr3.address, horseId)).toNumber()
            ).to.be.equal(1);
        });
        it("Verify balance of horse share is 2 after transfer to existing partner", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            await transferShares({to: addr3});
            expect(
                (await hardHatHorseFractionalization.balanceOf(addr3.address, horseId)).toNumber()
            ).to.be.equal(2);
        });
        it("Verify partner balance is 0 after transfer of share back to horse owner (governance)", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            await transferShares({from: addr3, to: addr1});
            expect(
                (await hardHatHorseFractionalization.balanceOf(addr3.address, horseId)).toNumber()
            ).to.be.equal(0);
        });
        it("Verify the number of partners is 2 after transferring the last share from partner 3", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            await transferShares({to: addr4});
            await transferShares({from: addr3, to: addr1});

            const partnership = await hardHatHorseFractionalization.getPartnership(horseId);
            const numPartners = partnership[0].filter((partner) => partner !== hre.ethers.constants.AddressZero).length;
            expect(numPartners).to.be.equal(2);
        });
        it("Verify number of partners is 2 and owner share count is 9 after fractionalization and transfer", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            const partnership = await hardHatHorseFractionalization.getPartnership(horseId);
            const partnerAddresses = partnership[0];
            const partnerShares = partnership[1];
            expect(partnerAddresses.length).to.be.equal(2);
            expect(partnerShares.length).to.be.equal(2);
            let ownerShareCount = 0;
            for (let i = 0; i < partnerAddresses.length; i++){
                if (partnerAddresses[i] === addr1.address){
                    ownerShareCount = partnerShares[i].toNumber();
                }
            }
            expect(ownerShareCount).to.be.equal(9);
        });
        it("Verify number of partners 2 and owner sharecount is 9 after fractionalization and 2 transfers", async function () {
            await fractionalizeHorse();
            await transferShares({to: addr3});
            await transferShares({from: addr3, to: addr2});
            const partnership = await hardHatHorseFractionalization.getPartnership(horseId);
            // console.log({partnership2});

            const partnerAddresses = partnership[0].filter((partner) => partner !== hre.ethers.constants.AddressZero);
            const partnerShares = partnership[1].filter((numShares) => numShares.toNumber() > 0);

            expect(partnerAddresses.length).to.be.equal(2);
            expect(partnerShares.length).to.be.equal(2);

            let ownerShareCount = 0;
            for (let i = 0; i < partnerAddresses.length; i++){
                if (partnerAddresses[i] === addr1.address){
                    ownerShareCount = partnerShares[i].toNumber();
                }
            }
            expect(ownerShareCount).to.be.equal(9);
        });

        it("Verify horse owner has 9 shares after fractionalization by fractionalization admin", async function () {
            await hardHatHorseFractionalization.grantRole(CONFIG_ADMIN_ROLE, addr3.address);
            const horseId = horses[addr1.address][1];
            // console.log({horseId, addr: addr1.address})
            await hardHatHorseFractionalization.adminFractionalize([addr1.address], [horseId]);
            expect(
                (await hardHatHorseFractionalization.balanceOf(addr1.address, horseId)).toNumber()
            ).to.be.equal(9);
        });

        it("Non owner fractionalized horse (Reverted)", async function () {
            await expect(
                hardHatHorseFractionalization.connect(addr2).fractionalize(horseId)
            ).to.be.reverted;
        });
        it("Horse owner attempts to fractionalize horse and contract paused (Reverted)", async function () {
            await hardHatHorseFractionalization.pause();
            const horseId2 = horses[addr1.address][1];
            await expect(
                hardHatHorseFractionalization.connect(addr1).fractionalize(horseId2)
            ).to.be.reverted;
        });
        it("Horse owner attempts to fractionalize horse and fractionalization paused (Reverted)", async function () {
            await hardHatHorseFractionalization.pauseFractionalization();
            const horseId2 = horses[addr1.address][1];
            await expect(
                hardHatHorseFractionalization.connect(addr1).fractionalize(horseId2)
            ).to.be.reverted;
        });

        it("Admin fractionalization attempted by account without fractionalization admin role (Reverted)", async function () {
            const horseId2 = horses[addr1.address][1];
            // console.log({horseId, addr: addr1.address})
            await expect(
                hardHatHorseFractionalization.connect(addr2).adminFractionalize([addr1.address], [horseId2]),
            ).to.be.reverted;
        });
    });

    describe("Reconstitution", function () {
        const horses = {};
        let horseId;

        const reconstitute = async ({id = horseId} = {}) => {
            await hardHatHorseFractionalization.connect(addr1).reconstitute(id);
        }

        beforeEach(async function () {
            await hardHatHorseDummy.connect(addr1).publicMint(2);
            horses[addr1.address] = [
                (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 0)).toNumber(),
                (await hardHatHorseDummy.tokenOfOwnerByIndex(addr1.address, 1)).toNumber(),
            ]
            await hardHatHorseDummy.connect(addr2).publicMint(2);
            horses[addr2.address] = [
                (await hardHatHorseDummy.tokenOfOwnerByIndex(addr2.address, 0)).toNumber(),
                (await hardHatHorseDummy.tokenOfOwnerByIndex(addr2.address, 1)).toNumber(),
            ]
            // console.log({horses});
            await hardHatHorseFractionalization.unpause();

            horseId = horses[addr1.address][0];
            // console.log({horseId, addr: addr1.address})
            await hardHatHorseFractionalization.connect(addr1).fractionalize(horseId);
        });

        it("Reconstitutes horse", async function () {
            await reconstitute();
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.false;
        });
        it("Reconstitute admin reconstitutes horse.", async function () {
            await hardHatHorseFractionalization.adminReconstitute([addr1.address], [horseId]);
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.false;
        });
        it("Verify partnership count is 0 after reconstitution", async function () {
            await reconstitute();
            expect(
                await hardHatHorseFractionalization.partnershipCount()
            ).to.be.equal(0);
        });
        it("Verify isFractionalized is false after reconstitution", async function () {
            await reconstitute();
            expect(
                await hardHatHorseFractionalization.isFractionalized(horseId)
            ).to.be.false;
        });
        it("Reconstitute a horse that is not fractionalized (Reverted)", async function () {
            await expect(
                hardHatHorseFractionalization.connect(addr1).reconstitute(horses[addr1.address][1])
            ).to.be.reverted;
        });
        it("Reconstitute horse where owner does not own all shares (Reverted)", async function () {
            await hardHatHorseFractionalization.connect(addr1)
                .safeTransferFrom(addr1.address, addr3.address, horseId, 1, "0x");
            await expect(
                hardHatHorseFractionalization.connect(addr1).reconstitute(horseId)
            ).to.be.reverted;
        });
        it("Reconstitute horse not owned by account (Reverted)", async function () {
            const testHorseId = horses[addr2.address][0]
            await hardHatHorseFractionalization.connect(addr2).fractionalize(testHorseId);
            await expect(
                hardHatHorseFractionalization.connect(addr1).reconstitute(testHorseId)
            ).to.be.reverted;
        });
    });

    describe("Burn partnership share", function () {
        beforeEach(async function () {
            await mintHorses();
            await fractionalizeHorse();
            await transferShares({from: addr1, to: addr2});
            await hardHatHorseFractionalization.grantRole(BURNER_ROLE, addr3.address);
        })

        it("Verify number of partners is 1 and owner share count is 9 after fractionalization and burning 1 partners shares", async function () {
            await hardHatHorseFractionalization.connect(addr2).setApprovalForAll(addr3.address, true);
            await hardHatHorseFractionalization.connect(addr3).burn(addr2.address, horseId, 1);

            // console.log(`Transfer 1 share from ${addr2.address} to ${addr3.address} completed`);

            const partnership = await hardHatHorseFractionalization.getPartnership(horseId);
            // console.log({partnership});

            const partnerAddresses = partnership[0].filter((partner) => partner !== hre.ethers.constants.AddressZero);
            const partnerShares = partnership[1].filter((numShares) => numShares.toNumber() > 0);

            expect(partnerAddresses.length).to.be.equal(1);
            expect(partnerShares.length).to.be.equal(1);

            let ownerShareCount = 0;
            for (let i = 0; i < partnerAddresses.length; i++) {
                if (partnerAddresses[i] === addr1.address) {
                    ownerShareCount = partnerShares[i].toNumber();
                }
            }

            expect(ownerShareCount).to.be.equal(9);
        });
        it("Verify number of partners is 1 and owner share count is 9 after fractionalization and burning 1 partners shares", async function () {
            await hardHatHorseFractionalization.connect(addr2).setApprovalForAll(addr3.address, true);
            await hardHatHorseFractionalization.connect(addr3).burnBatch(addr2.address, [horseId], [1]);

            // console.log(`Transfer 1 share from ${addr2.address} to ${addr3.address} completed`);

            const partnership = await hardHatHorseFractionalization.getPartnership(horseId);
            // console.log({partnership});

            const partnerAddresses = partnership[0].filter((partner) => partner !== hre.ethers.constants.AddressZero);
            const partnerShares = partnership[1].filter((numShares) => numShares.toNumber() > 0);

            expect(partnerAddresses.length).to.be.equal(1);
            expect(partnerShares.length).to.be.equal(1);

            let ownerShareCount = 0;
            for (let i = 0; i < partnerAddresses.length; i++){
                if (partnerAddresses[i] === addr1.address){
                    ownerShareCount = partnerShares[i].toNumber();
                }
            }

            expect(ownerShareCount).to.be.equal(9);
        });
        it("Burn token using account with out burner role and approval (Reverted)", async function () {
            await hardHatHorseFractionalization.connect(addr2).setApprovalForAll(addr4.address, true);
            await expect(
                hardHatHorseFractionalization.connect(addr4).burn(addr2.address, horseId, 1)
            ).to.be.reverted;
        });
        it("Burn token using account with burner and no approval (Reverted)", async function () {
            await expect(
                hardHatHorseFractionalization.connect(addr3).burn(addr2.address, horseId, 1)
            ).to.be.reverted;
        });
        it("Burn tokens using account with out burner role and approval (Reverted)", async function () {
            await hardHatHorseFractionalization.connect(addr2).setApprovalForAll(owner.address, true);
            await expect(
                hardHatHorseFractionalization.connect(addr4).burnBatch(addr2.address, [horseId], [1])
            ).to.be.reverted;
        });
        it("Burn tokens using account with burner and no approval (Reverted)", async function () {
            await expect(
                hardHatHorseFractionalization.connect(addr3).burnBatch(addr2.address, [horseId], [1])
            ).to.be.reverted;
        });
    })

    describe("Miscellaneous", function () {
        it("Supports ERC 165", async function() {
            const supports = await hardHatHorseFractionalization.supportsInterface("0x01ffc9a7");
            expect(supports).to.be.true;
        })
        it("Supports ERC 2981", async function() {
            const supports = await hardHatHorseFractionalization.supportsInterface("0x2a55205a");
            expect(supports).to.be.true;
        })
        it("Supports ERC 1155", async function() {
            const supports = await hardHatHorseFractionalization.supportsInterface("0xd9b67a26");
            expect(supports).to.be.true;
        })
    });

})