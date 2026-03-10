const {expect} = require("chai");
const fs = require("fs");
const path = require("path");

const diamondInfo = require("../diamondInfo.json");
const {ethers} = require("hardhat");

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
        console.error(`e`, e)
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

const getFacet = async ({name, args = [], upgradeable = true}) => {
    // console.log(`[getFacet] name: ${name}`);
    const contractFactory = await hre.ethers.getContractFactory(name);
    const deployedFacet = await contractFactory.deploy(...args);
    return {
        name,
        deployedFacet,
        upgradeable
    }
}

const addPayoutTiers = async ({hardHatHorse}) => {
    const pct5 = {
        payoutTierId: 5,
        description : "5 Pct Payout",
        price: ethers.utils.parseEther("0.1"),
        maxPerTx: 5,
        payoutPct: 500,
        maxSupply: 0,
        paused: false,
        valid: true,
    }

    // Set payout tier information
    await hardHatHorse.setPayoutTier(pct5.payoutTierId, pct5.description, pct5.price, pct5.maxPerTx, pct5.payoutPct, pct5.maxSupply, pct5.paused, pct5.valid);

    return {
        pct5
    }
}

describe("Horse V2 Test Cases", function () {

    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addr4
    let addrs;

    let horseContract;
    let hardHatHorse;
    let horseContractAddress;

    const seasonInfos = [
        { seasonId: 2024, description: "Silks 2024 Horse Season", paused: false, valid: true}];
    const payoutTiers = [
        { tierId: 1, description: "1 Pct Payout", price: ethers.utils.parseEther('.0001'), maxPerTx: 100, payoutPct: 100, maxSupply: 0, paused: false, valid: true}
    ];

    beforeEach(async function () {
        [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();

        const facets = await Promise.all(diamondInfo.facets.map(name => getFacet({name, owner})));

        // console.log(`[main] facets: ${JSON.stringify(facets, null, 4)}`);

        const diamondCut = [];
        const contractSignatures = [];
        const abis = [];
        for(let i = 0; i < facets.length; i++){
            // console.log({facet: facets[i]})
            const { name, deployedFacet } = facets[i];
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
            abis.push(getAbi({contractName: name, folder: "facets/"}));
        }
        abis.push(getAbi({contractName: diamondInfo.name}));

        // console.log(JSON.stringify({contractSignatures}, null, 4))
        const contractAbi = abis.flat().reduce((acc, func) => {
            const signature = getFunctionSignature({func});
            if(acc.findIndex(item => getFunctionSignature({func: item}) === signature) === -1){
                acc.push(func);
            }
            return acc;
        }, []);

        // console.log(JSON.stringify(contractAbi))


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

        const args = [
            owner.address,
            "Silks Horse V2",
            "SILKS_HORSE_V2",
            "https://nft.silks.io/metadata/c1/",
            8257,
            owner.address,
            800, // 8 pct
            0,
            seasonInfos,
            payoutTiers
        ];

        horseContract = await hre.ethers.getContractFactory(diamondInfo.name);
        hardHatHorse = await horseContract.deploy(...args);
        await hardHatHorse.deployed();

        horseContractAddress = hardHatHorse.address;

        hardHatHorse = await hre.ethers.getContractAt(contractAbi, horseContractAddress);

        const initFacet = facets.find((facet) => facet.name.indexOf("DiamondInit") > -1 ).deployedFacet;
        const callData = (new hre.ethers.utils.Interface(["function init() external"])).encodeFunctionData("init");

        // console.log(`[main] diamond cut: ${JSON.stringify(diamondCut, null, 4)}`);

        const diamondCutTx = await hardHatHorse.diamondCut(diamondCut, initFacet.address, callData);
        await diamondCutTx.wait();

        await hardHatHorse.unpause();
    });

    describe("WriteableFacet Contract", function () {
        // Test the setRoleAdmin function
        it("should set the admin role for a specified role", async function () {
            const role = ethers.utils.id("TEST_ROLE"); // Replace with an actual role ID
            const adminRole = ethers.utils.id("ADMIN_ROLE"); // Replace with an actual admin role ID

            // Grant the CONTRACT_ADMIN_ROLE to the owner
            await hardHatHorse.grantRole(ethers.utils.id("CONTRACT_ADMIN_ROLE"), owner.address);

            // Set the admin role
            await hardHatHorse.setRoleAdmin(role, adminRole);

            // Check if the admin role is set correctly
            const returnedAdminRole = await hardHatHorse.getRoleAdmin(role);
            expect(returnedAdminRole).to.equal(adminRole);
        });

        it('should check have role', async function () {
            const role = ethers.utils.id("TEST_ROLE"); // Replace with an actual role ID
            await hardHatHorse.grantRole(role, addr1.address);

            const hasRole = await hardHatHorse.hasRole(role, addr1.address);
            expect(hasRole).to.be.true;
        });

        // Test the setSeasonInfo function
        it("should set season information", async function () {
            const seasonId = 2025;
            const description = "2025 Season";
            const paused = false;
            const valid = true;

            // Grant the MINT_ADMIN_ROLE to the owner
            await hardHatHorse.grantRole(ethers.utils.id("MINT_ADMIN_ROLE"), owner.address);

            // Set season information
            await hardHatHorse.setSeasonInfo(seasonId, description, paused, valid);

            // Retrieve and verify the set season information
            const [returnedSeasonId, returnedDescription, returnedPaused, returnedValid] = await hardHatHorse.seasonInfo(seasonId);
            expect(returnedSeasonId).to.equal(seasonId);
            expect(returnedDescription).to.equal(description);
            expect(returnedPaused).to.equal(paused);
            expect(returnedValid).to.equal(valid);
        });

        // Test the setPayoutTier function
        it("should set payout tier information", async function () {

            const {pct5} = await addPayoutTiers({hardHatHorse});

            // Retrieve and verify the set payout tier information
            const [returnedTierId, returnedDescription, returnedPrice, returnedMaxPerTx, returnedPayoutPct, returnedMaxSupply, returnedPaused, returnedValid] = await hardHatHorse.payoutTier(pct5.payoutTierId);
            expect(returnedTierId).to.equal(pct5.payoutTierId);
            expect(returnedDescription).to.equal(pct5.description);
            expect(returnedPrice).to.equal(pct5.price);
            expect(returnedMaxPerTx).to.equal(pct5.maxPerTx);
            expect(returnedPayoutPct).to.equal(pct5.payoutPct);
            expect(returnedMaxSupply).to.equal(pct5.maxSupply);
            expect(returnedPaused).to.equal(pct5.paused);
            expect(returnedValid).to.equal(pct5.valid);
        });

        // Test the setBaseURI function
        it("should set the base URI for metadata of NFTs", async function () {
            const baseURI = "https://example.com/";

            // Grant the MINT_ADMIN_ROLE to the owner
            await hardHatHorse.grantRole(ethers.utils.id("MINT_ADMIN_ROLE"), owner.address);

            // Set the base URI
            await hardHatHorse.setBaseURI(baseURI);

            // Retrieve and verify the set base URI
            const returnedBaseURI = await hardHatHorse.baseURI();
            expect(returnedBaseURI).to.equal(baseURI);
        });

        it('should allow external mint address', async function () {
            const dummyDeployer = await hre.ethers.getContractFactory("DummyExternalTest");
            const dummyContract = await dummyDeployer.deploy(horseContractAddress);
            await dummyContract.deployed();
            const dummyAddress = dummyContract.address;
            await hardHatHorse.allowExternalMintAddress(dummyAddress);

            const allowed = await hardHatHorse.isAllowedExternalMintAddress(dummyAddress)
            expect(allowed).to.be.true;
        })

        it('should not allow non contract address for external mint', async function () {
            await expect(hardHatHorse.allowExternalMintAddress(addr1.address)).to.be.reverted;
        })

        // Test the setHorsePayoutTier function
        it("should set the payout tier for a specific horse token", async function () {
            const {pct5} = await addPayoutTiers({hardHatHorse});

            const seasonId = 2024;

            // Mint a horse token to the user
            await hardHatHorse.airdrop(seasonId, 1, 1, addr1.address);

            const tokenId = (await hardHatHorse.tokenOfOwnerByIndex(addr1.address, 0)).toNumber();
            
            // Set the payout tier for the horse token
            await hardHatHorse.setHorsePayoutTier(tokenId, pct5.payoutTierId);

            // Retrieve and verify the set payout tier for the horse token
            const returnedPayoutTier = await hardHatHorse.horsePayoutTier(tokenId);
            expect(returnedPayoutTier.tierId).to.equal(pct5.payoutTierId);
        });

        // Add more test cases for other functions as needed

        // Test the pause function
        it("should pause the contract", async function () {
            // Pause the contract
            await hardHatHorse.pause();

            // Check if the contract is paused
            const paused = await hardHatHorse.paused();
            expect(paused).to.equal(true);
        });

        // Test the unpause function
        it("should unpause the contract", async function () {
            // Pause and then unpause the contract
            await hardHatHorse.pause();
            await hardHatHorse.unpause();

            // Check if the contract is unpaused
            const paused = await hardHatHorse.paused();
            expect(paused).to.equal(false);
        });

        // Test the pauseHorsePurchases function
        it("should pause horse purchases", async function () {
            // Pause horse purchases
            await hardHatHorse.pauseHorsePurchases();

            // Check if horse purchases are paused
            const paused = await hardHatHorse.horsePurchasesPaused();
            expect(paused).to.equal(true);
        });

        // Test the unpauseHorsePurchases function
        it("should unpause horse purchases", async function () {
            // Pause and then unpause horse purchases
            await hardHatHorse.pauseHorsePurchases();
            await hardHatHorse.unpauseHorsePurchases();

            // Check if horse purchases are unpaused
            const paused = await hardHatHorse.horsePurchasesPaused();
            expect(paused).to.equal(false);
        });

        // Add more test cases for other functions as needed

        // Test the setContractAdminRoleMember function
        it("should set or revoke the CONTRACT_ADMIN_ROLE for a specific address", async function () {
            const adminAddress = addr1.address;

            // Set the CONTRACT_ADMIN_ROLE for the adminAddress
            await hardHatHorse.setContractAdminRole(adminAddress, true);

            // Check if adminAddress has the CONTRACT_ADMIN_ROLE
            const hasRole = await hardHatHorse.hasContractAdminRole(adminAddress);
            expect(hasRole).to.equal(true);

            // Revoke the CONTRACT_ADMIN_ROLE for the adminAddress
            await hardHatHorse.setContractAdminRole(adminAddress, false);

            // Check if adminAddress does not have the CONTRACT_ADMIN_ROLE
            const hasRoleAfterRevoke = await hardHatHorse.hasContractAdminRole(adminAddress);
            expect(hasRoleAfterRevoke).to.equal(false);
        });

        // Test the setMintAdminRoleMember function
        it("should set or revoke the MINT_ADMIN_ROLE for a specific address", async function () {
            const adminAddress = addr1.address;

            // Set the MINT_ADMIN_ROLE for the adminAddress
            await hardHatHorse.setMintAdminRole(adminAddress, true);

            // Check if adminAddress has the MINT_ADMIN_ROLE
            const hasRole = await hardHatHorse.hasMintAdminRole(adminAddress);
            expect(hasRole).to.equal(true);

            // Revoke the MINT_ADMIN_ROLE for the adminAddress
            await hardHatHorse.setMintAdminRole(adminAddress, false);

            // Check if adminAddress does not have the MINT_ADMIN_ROLE
            const hasRoleAfterRevoke = await hardHatHorse.hasMintAdminRole(adminAddress);
            expect(hasRoleAfterRevoke).to.equal(false);
        });

        // Test the setRoyaltyInfo function
        it("should set royalty information", async function () {
            const receiver = owner.address;
            const basePoints = 1000; // 10%
            const tokenId = 1;
            const salePrice = ethers.utils.parseEther('0.1');

            // Set royalty information
            await hardHatHorse.setRoyaltyInfo(receiver, basePoints);

            await hardHatHorse.airdrop(2024, 1, 1, addr1.address);

            // Retrieve and verify the set royalty information
            const [royaltyReceiver, royalty] = await hardHatHorse.royaltyInfo(tokenId, salePrice);
            expect(royaltyReceiver).to.equal(receiver);
            expect(royalty).to.equal(salePrice.mul(basePoints).div(10000));
        });

        it('Should withdraw funds from contract', async function () {
            const originalBalance = await ethers.provider.getBalance(addr2.address)
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            const purchaseTransaction = await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });;
            await purchaseTransaction.wait();
            const contractBalance = await ethers.provider.getBalance(hardHatHorse.address)
            const tx = await hardHatHorse.withdrawFunds(addr2.address);
            await tx.wait();
            const postWithdrawContractBalance = await ethers.provider.getBalance(hardHatHorse.address);
            expect(postWithdrawContractBalance).to.be.equal(0);
            const postWithdrawToBalance = await ethers.provider.getBalance(addr2.address);
            const transferredAmount = postWithdrawToBalance.sub(originalBalance);
            expect(transferredAmount).to.be.equal(contractBalance);
        })

        it('should set max horses per wallet', async function () {
            await hardHatHorse.setMaxHorsesPerWallet(100);
            const value = await hardHatHorse.maxHorsesPerWallet();
            expect(value).to.be.equal(100);
        })
    });

    describe("ReadableFacet Contract", function () {
        // Test the seasonInfo function
        it("should return season information", async function () {
            const seasonId = seasonInfos[0].seasonId;
            const [returnedSeasonId] = await hardHatHorse.seasonInfo(seasonId);
            // Add your assertions here
            expect(returnedSeasonId).to.equal(seasonId);
        });

        // Test the payoutTier function
        it("should return payout tier information", async function () {
            const payoutTierId = payoutTiers[0].tierId;
            const [returnedTierId] = await hardHatHorse.payoutTier(payoutTierId);
            // Add your assertions here
            expect(returnedTierId).to.equal(payoutTierId);
        });
        // Test the horsePurchasesPaused function
        it("should return whether horse purchases are paused", async function () {
            const paused = await hardHatHorse.horsePurchasesPaused();
            // Add your assertions here
            expect(paused).to.equal(false); // Replace with the expected result
        });
        it('address should not be allowed for external mint', async function () {
            const dummyDeployer = await hre.ethers.getContractFactory("DummyExternalTest");
            const dummyContract = await dummyDeployer.deploy(horseContractAddress);
            await dummyContract.deployed();
            const allowed = await hardHatHorse.isAllowedExternalMintAddress(dummyContract.address)
            expect(allowed).to.be.false;
        })
    });

    describe('ERC721Facet', function () {
        it('should purchase 1 horse correctly', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });

            // Check if the sender owns the purchased horses
            expect(await hardHatHorse.balanceOf(owner.address)).to.equal(quantity);
        });

        it('purchased token should be 8257', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });

            // Check if the sender owns the purchased horses
            expect(await hardHatHorse.tokenOfOwnerByIndex(owner.address, 0)).to.equal(8257);
        });

        it('next available token after purchase should be 8258', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });

            // Check if the sender owns the purchased horses
            expect(await hardHatHorse.nextAvailableTokenId()).to.equal(8258);
        });

        it('should purchase multiple horses correctly', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 2;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });

            // Check if the sender owns the purchased horses
            expect(await hardHatHorse.balanceOf(owner.address)).to.equal(quantity);
        });

        it('should revert with invalid payout tier', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await expect(hardHatHorse.purchase(seasonId, 2, quantity, { value  })).to.be.reverted;
        });

        it('should revert with invalid season', async function () {
            // Assuming you have set up valid season and payout tier information
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await expect(hardHatHorse.purchase(2025, payoutTier.tierId, quantity, { value  })).to.be.reverted;
        });

        it('should revert because exceeds max horses per wallet', async function () {
            await hardHatHorse.setMaxHorsesPerWallet(1);

            const seasonId = 2024;
            const quantity = 2;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await expect(hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  })).to.be.reverted;
        });

        it('should revert because exceeds max horses per tier', async function () {
            const testTier = payoutTiers[0];
            testTier.maxSupply = 1;

            await hardHatHorse.setPayoutTier(
                testTier.tierId, testTier.description, testTier.price, testTier.maxPerTx, testTier.payoutPct,
                testTier.maxSupply, testTier.paused, testTier.valid
            );

            const seasonId = 2024;
            const quantity = 2;

            const value = testTier.price.mul(quantity);

            // Purchase horses
            await expect(hardHatHorse.purchase(seasonId, testTier.tierId, quantity, { value  })).to.be.reverted;
        });

        it("should return season information for horse", async function () {
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            const value = (quantity*payoutTier.price);

            // Purchase horses
            await hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value  });

            const tokenId = await hardHatHorse.tokenOfOwnerByIndex(owner.address, 0);

            const [_,returnedSeasonId] = await hardHatHorse.horseSeasonInfo(tokenId);

            expect(returnedSeasonId).to.be.equal(seasonId);
        });

        it('should airdrop horses correctly', async function () {
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            // Airdrop horses
            await hardHatHorse.airdrop(seasonId, payoutTier.tierId, quantity, addr1.address);

            // Check if the recipient owns the airdropped horses
            expect(await hardHatHorse.balanceOf(addr1.address)).to.equal(quantity);
        });

        it('should call external mint', async function () {
            const dummyDeployer = await hre.ethers.getContractFactory("DummyExternalTest");
            const dummyContract = await dummyDeployer.deploy(horseContractAddress);
            await dummyContract.deployed();

            await hardHatHorse.allowExternalMintAddress(dummyContract.address);

            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];
            // Airdrop horses
            await dummyContract.testExternalMint(seasonId, payoutTier.tierId, quantity, addr1.address);

            expect(await hardHatHorse.balanceOf(addr1.address)).to.equal(quantity);
        });

        it('should prevent purchase when paused', async function () {
            // Pause the contract
            await hardHatHorse.pause();
            // Assuming you have set up valid season and payout tier information
            const seasonId = 2024;
            const quantity = 1;

            const payoutTier = payoutTiers[0];

            // Attempt to purchase horses (expecting it to fail due to contract being paused)
            await expect(hardHatHorse.purchase(seasonId, payoutTier.tierId, quantity, { value: (quantity*payoutTier.price) })).to.be.reverted;
        });

        it('should support interface ERC 165', async function () {
            const supportsInterface = await hardHatHorse.supportsInterface("0x80ac58cd");
            expect(supportsInterface).to.be.true;
        })
    });
});