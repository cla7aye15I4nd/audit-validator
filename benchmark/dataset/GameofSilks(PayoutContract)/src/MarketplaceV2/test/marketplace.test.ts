import { expect } from "chai";
import ShortUniqueId from "short-unique-id";
// import { ethers } from "hardhat";
import { ethers } from "hardhat";
import {
	getSignatures,
	getFacet,
	getFunctionSignature,
	getAbi,
} from "./helpers";
import diamondInfo from "../diamondInfo.json";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { AddressLike, Contract } from "ethers";
import {
	IDiamondWritableInternal,
	MarketplaceDiamondABI,
	SilksDummy,
} from "../typechain-types";
import { ListingStruct } from "../typechain-types/hardhat-diamond-abi/HardhatDiamondABI.sol/MarketplaceDiamondABI";
import { BigNumberish } from "ethers";
import { BytesLike } from "ethers";

const uid = new ShortUniqueId({ length: 30 });

const getBalance = async (address: string) => {
	const provider = ethers.provider;
	return await provider.getBalance(address);
};

// @ts-ignore JSH: Type error, this is fine.
BigInt.prototype.toJSON = function () {
	const int = Number.parseInt(this.toString());
	return int ?? this.toString();
};

type ListingType = {
	listingId: string;
	listingAddress: string;
	seller: string;
	buyer: string;
	tokenId: number;
	numListed: number;
	pricePer: bigint;
	royaltyPct: number;
	active: boolean;
	valid: boolean;
};

const LISTINGS_PAUSED = ethers.encodeBytes32String(
	"silks.contracts.paused.Listings"
);

describe("Marketplace V2 Test", function () {
	let owner: SignerWithAddress;
	let addr1: SignerWithAddress;
	let addr2: SignerWithAddress;
	let addr3: SignerWithAddress;
	let addr4: SignerWithAddress;
	let addrs: SignerWithAddress[];

	let hardHatMarketplace: MarketplaceDiamondABI;
	let contractAbi;
	let hardHatAvatar: SilksDummy;

	let listTypes: [string, string, number, boolean, boolean][];
	const royaltyBasePoints = 800;

	beforeEach(async function () {
		// @ts-ignore JSH: Type error, getSigners does exist on this object
		[owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();

		const avatarContract = await ethers.getContractFactory("SilksDummy");
		hardHatAvatar = await avatarContract.deploy();

		await hardHatAvatar.connect(addr1).publicMint(10);

		const facets = await Promise.all(
			diamondInfo.facets.map((info) => getFacet({ info }))
		);

		//  IDiamondWritableInternal.FacetCutStruct[],
		// AddressLike
		// BytesLike
		type DiamondCutPayload = [
			IDiamondWritableInternal.FacetCutStruct[],
			AddressLike,
			BytesLike
		];
		const diamondCut: IDiamondWritableInternal.FacetCutStruct[] = [];
		const contractSignatures: {
			contractName: string;
			contractAddress: string;
			signaturesToSelectors: any[];
		}[] = [];
		const abis: any[] = [];
		for (let i = 0; i < facets.length; i++) {
			const { info, deployedFacet } = facets[i];
			const signaturesToSelectors = await getSignatures({ deployedFacet });
			diamondCut.push({
				target: await deployedFacet.getAddress(),
				action: 0n,
				selectors: signaturesToSelectors.map((val) => val.selector),
			});
			contractSignatures.push({
				contractName: info.name,
				contractAddress: await deployedFacet.getAddress(),
				signaturesToSelectors,
			});
			abis.push(getAbi({ contractName: info.name, folder: info.folder }));
		}
		abis.push(getAbi({ contractName: diamondInfo.name }));

		contractAbi = abis.flat().reduce((acc: any[], func) => {
			const signature = getFunctionSignature({ func });
			if (
				acc.findIndex(
					(item) => getFunctionSignature({ func: item }) === signature
				) === -1
			) {
				acc.push(func);
			}
			return acc;
		}, []);

		const duplicateFunctions: any[] = [];
		for (let i = 0; i < contractSignatures.length; i++) {
			const contractSignature = contractSignatures[i];
			const currentSelectors = contractSignature.signaturesToSelectors;
			for (let j = 0; j < currentSelectors.length; j++) {
				const currentSelector = currentSelectors[j].selector;
				// console.log(`[main] currentSelector: ${currentSelector}`);
				for (let k = 0; k < contractSignatures.length; k++) {
					if (k !== i) {
						const testContractSignature = contractSignatures[k];
						const testSelectors = testContractSignature.signaturesToSelectors;
						for (let l = 0; l < testSelectors.length; l++) {
							const testSelector = testSelectors[l].selector;
							// console.log(`            testSelector: ${testSelector}`);
							if (testSelector === currentSelector) {
								if (
									duplicateFunctions.findIndex(
										(val) => val.selector === testSelector
									) === -1
								) {
									duplicateFunctions.push({
										contract1: contractSignature.contractName,
										contract2: testContractSignature.contractName,
										function: testSelectors[l].function,
										selector: testSelector,
									});
								}
							}
						}
					}
				}
			}
		}

		if (duplicateFunctions.length > 0) {
			console.log(`[main] duplicate functions found:`, duplicateFunctions);
			throw new Error("duplicate functions found");
		}

		const args = [owner.address];

		const marketplaceContract = await ethers.getContractFactory(
			diamondInfo.name
		);

		// @ts-ignore JSH: Type error, this is fine.
		hardHatMarketplace = await marketplaceContract.deploy(...args);
		await hardHatMarketplace.waitForDeployment();

		const hardHatMarketplaceAddress = await hardHatMarketplace.getAddress();

		// console.log(`hardHatMarketplaceAddress: ${hardHatMarketplaceAddress}`);

		// @ts-ignore JSH: Type error, this is fine.
		hardHatMarketplace = await ethers.getContractAt(
			contractAbi,
			hardHatMarketplaceAddress
		);

		// console.log({hardHatMarketplace});

		// console.log({facets});

		const initFacet = facets.find(
			(facet) => facet.info.name.indexOf("DiamondInit") > -1
		)?.deployedFacet;

		// console.log({ initFacet, initFacetAddress: initFacet?.target });

		listTypes = [[await hardHatAvatar.getAddress(), "avatar", 721, true, true]];

		const initArgs = [
			listTypes,
			owner.address,
			royaltyBasePoints,
			"0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c",
		];
		// console.log(`initArgs: ${JSON.stringify(initArgs, null, 4)}`);

		const iface = new ethers.Interface([
			"function init((address,string,uint256,bool,bool)[],address,uint256,address) external",
		]);
		const callData = iface.encodeFunctionData("init", initArgs);

		const initFacetAddress = await initFacet?.getAddress();
		diamondCut.forEach((cut) => {
			cut.selectors = cut.selectors.map((selector) => {
				// Check if the selector has the correct length and prefix
				if (
					typeof selector === "string" &&
					selector.length === 8 &&
					!selector.startsWith("0x")
				) {
					// Add '0x' prefix and return the corrected selector
					return "0x" + selector;
				} else {
					// If already correct, return as is
					return selector;
				}
			});
		});

		const diamondCutTx = await hardHatMarketplace.diamondCut(
			diamondCut,
			initFacetAddress!,
			callData
		);
		await diamondCutTx.wait();
	});

	describe("Diamond Admin Facets", function () {
		describe("MarketplaceAdminWriteableFacet", function () {
			it("pause", async function () {
				await hardHatMarketplace.unpause();
				await hardHatMarketplace.pause();
				const isPaused = await hardHatMarketplace.paused();
				expect(isPaused).to.be.true;
			});
			// [ '0x716A12D9A708c99E4bAc39970a74BC4f92349432', 800n ]
			it("setRoyaltyInfo", async function () {
				// @ts-ignore
				await hardHatMarketplace.setRoyaltyInfo(addr3.address, 200n);
				// @ts-ignore
				const info = await hardHatMarketplace.getRoyaltyInfo();
				expect(info[0]).to.be.equal(addr3.address);
				expect(info[1]).to.be.equal(200n);
			});
			it("withdrawFunds", async function () {
				const contractAddress = await hardHatMarketplace.getAddress();
				await owner.sendTransaction({
					to: contractAddress,
					value: ethers.parseEther("1.0"),
				});

				const contractBalanceBefore = await getBalance(contractAddress);
				const receiverBalanceBefore = await getBalance(addr3.address);
				await hardHatMarketplace.withdrawFunds(addr3.address);
				const contractBalanceAfter = await getBalance(contractAddress);
				const receiverBalanceAfter = await getBalance(addr3.address);

				expect(contractBalanceAfter).to.be.equal(0);
				expect(receiverBalanceAfter).to.be.equal(
					contractBalanceBefore + receiverBalanceBefore
				);
			});
			it("reverted because non admin tried to withdraw funds", async function () {
				await expect(
					hardHatMarketplace.connect(addr1).withdrawFunds(addr3.address)
				).to.revertedWith(/AccessControl/);
			});
			it("revert because non admin tried to pause the contact", async function () {
				await expect(hardHatMarketplace.connect(addr3).pause()).to.revertedWith(
					/AccessControl/
				);
			});
			it("revert because non admin tried to unpause the contact", async function () {
				await expect(
					hardHatMarketplace.connect(addr3).unpause()
				).to.revertedWith(/AccessControl/);
			});
		});
	});

	describe("Glossary Facets", function () {
		const avatarContractGlossaryName = "Avatar";
		let avatarContractAddress: string;
		const setTestAddress = async () => {
			avatarContractAddress = await hardHatAvatar.getAddress();
			// @ts-ignore SI: Is valid function
			await hardHatMarketplace.addContractGlossaryEntry(
				avatarContractGlossaryName,
				avatarContractAddress
			);
		};
		describe("ContractGlossaryReadableFacet", function () {
			beforeEach(async function () {
				await setTestAddress();
			});
			it("getAddressFromContractGlossary", async function () {
				// @ts-ignore
				const contractAddress =
					await hardHatMarketplace.getAddressFromContractGlossary("Avatar");
				expect(contractAddress).to.be.equal(avatarContractAddress);
			});

			it("getNameFromContractGlossary", async function () {
				// @ts-ignore
				const contractName =
					await hardHatMarketplace.getNameFromContractGlossary(
						avatarContractAddress
					);
				expect(contractName).to.be.equal(avatarContractGlossaryName);
			});

			it("getContractGlossaryEntries", async function () {
				// @ts-ignore
				const entries = await hardHatMarketplace.getContractGlossaryEntries();
				expect(entries.length).to.be.equal(1);
				expect(entries[0][1]).to.be.equal(avatarContractGlossaryName);
				expect(entries[0][2]).to.be.equal(avatarContractAddress);
			});
		});
	});

	describe("Listing Facets", function () {
		const listingId = uid.rnd();
		const pricePer = ethers.parseEther("0.0001");
		const soldTokenId = 1;
		const numListed = 1;

		const getListingStruct = async (
			listIdInBytes: string
		): Promise<ListingStruct> => {
			return {
				listingId: listIdInBytes,
				listingAddress: await hardHatAvatar.getAddress(),
				seller: addr1.address,
				buyer: ethers.ZeroAddress,
				tokenId: soldTokenId,
				numListed: numListed,
				pricePer: pricePer,
				royaltyBasePoints: royaltyBasePoints,
				active: true,
				valid: true,
			};
		};

		describe("ListingAdminWriteableFacet", function () {
			let listing: ListingStruct;
			beforeEach(async function () {
				await hardHatMarketplace.unpause();
				await hardHatAvatar
					.connect(addr1)
					.setApprovalForAll(await hardHatMarketplace.getAddress(), true);
				listing = await getListingStruct(ethers.encodeBytes32String(listingId));
				// console.log({listing});
				// @ts-ignore
				await hardHatMarketplace.createListings([listing]);
			});

			it("createListings", async function () {
				// console.log("Listing created")
				const storedListing = await hardHatMarketplace.getListing(
					listing.listingId
				);
				// console.log({storedListing});
				expect(storedListing[0]).to.be.equal(listing.listingId);
			});

			it("updateListings", async function () {
				listing.active = false;
				// @ts-ignore
				await hardHatMarketplace.updateListings([listing]);

				const storedListing = await hardHatMarketplace.getListing(
					listing.listingId
				);
				expect(storedListing.active).to.be.false;
			});

			it("pauseListings", async function () {
				// @ts-ignore
				await hardHatMarketplace.pauseListings();
				const listingsPaused = await hardHatMarketplace.listingsPaused();
				expect(listingsPaused).to.be.true;
			});

			it("unpauseListings", async function () {
				// @ts-ignore
				await hardHatMarketplace.pauseListings();
				// @ts-ignore
				await hardHatMarketplace.unpauseListings();
				const listingsPaused = await hardHatMarketplace.listingsPaused();
				expect(listingsPaused).to.be.false;
			});

			it("grantListingAdminRole", async function () {
				// @ts-ignore
				await hardHatMarketplace.grantListingAdminRole(addr3.address);
				// @ts-ignore
				const isListingAdmin = await hardHatMarketplace.hasListingAdminRole(
					addr3.address
				);
				expect(isListingAdmin).to.be.true;
			});

			it("setListingType", async function () {
				// @ts-ignore
				await hardHatMarketplace.setListingType({
					contractAddress: ethers.ZeroAddress,
					description: "Test",
					ercStandard: 1975,
					active: true,
					valid: true,
				});

				const listingType = await hardHatMarketplace.getListingType(
					ethers.ZeroAddress
				);
				expect(listingType.valid).to.be.true;
			});

			it("revert because non admin tried to create listings", async function () {
				// console.log("Listing created")
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).createListings([listing])
				).to.revertedWith(/AccessControl/);
			});
			it("revert because non admin tried to updated listings", async function () {
				// console.log("Listing created")
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).updateListings([listing])
				).to.revertedWith(/AccessControl/);
			});
			it("revert because non admin tried to pause listings", async function () {
				// console.log("Listing created")
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).pauseListings()
				).to.revertedWith(/AccessControl/);
			});
			it("revert because non admin tried to unpause listings", async function () {
				// console.log("Listing created")
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).unpauseListings()
				).to.revertedWith(/AccessControl/);
			});

			it("revert because non admin tried to grant role", async function () {
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).grantListingAdminRole(addr3.address)
				).to.revertedWith(/AccessControl/);
			});

			it("revert because non admin tried to set a listing type", async function () {
				await expect(
					// @ts-ignore
					hardHatMarketplace.connect(addr3).setListingType({
						contractAddress: ethers.ZeroAddress,
						description: "Test",
						ercStandard: 1975,
						active: true,
						valid: true,
					})
				).to.revertedWith(/AccessControl/);
			});
		});

		describe("ListingReadableFacet", function () {
			let listing: ListingStruct;
			beforeEach(async function () {
				await hardHatMarketplace.unpause();
				await hardHatAvatar
					.connect(addr1)
					.setApprovalForAll(await hardHatMarketplace.getAddress(), true);
				listing = await getListingStruct(ethers.encodeBytes32String(listingId));
				// console.log({listing});
				await hardHatMarketplace
					.connect(addr1)
					.createListing(
						listing.listingId,
						listing.listingAddress,
						listing.tokenId,
						listing.numListed,
						listing.pricePer,
						listing.royaltyBasePoints,
						listing.active
					);
			});
			it("getListingType", async function () {
				const avatarAddress = await hardHatAvatar.getAddress();
				const [listingAddress] = await hardHatMarketplace.getListingType(
					avatarAddress
				);
				expect(listingAddress).to.be.equal(avatarAddress);
			});

			it("getActiveListingIds", async function () {
				const listingIds = await hardHatMarketplace.getActiveListingIds();
				// @ts-ignore
				expect(listingIds.indexOf(listing.listingId)).to.be.gt(-1);
			});

			it("getTokensListedForListing", async function () {
				const tokens = await hardHatMarketplace.getTokensListedForListing(
					listing.listingAddress
				);
				// console.log({tokens});
				// @ts-ignore
				expect(tokens.indexOf(BigInt(`${listing.tokenId}`))).to.be.gt(-1);
			});

			it("getSupportedERCStandards", async function () {
				const supportedERCStandards =
					await hardHatMarketplace.getSupportedERCStandards();
				// console.log({supportedERCStandards});
				expect(supportedERCStandards.length).to.be.equal(2);
			});
		});

		describe("ListingWriteableFacet", function () {
			beforeEach(async function () {
				await hardHatMarketplace.unpause();
				await hardHatAvatar
					.connect(addr1)
					.setApprovalForAll(await hardHatMarketplace.getAddress(), true);
			});

			describe("createListing", function () {
				it("success", async function () {
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					await hardHatMarketplace
						.connect(addr1)
						.createListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							listing.active
						);
					// console.log("Listing created")
					const storedListing = await hardHatMarketplace.getListing(
						listing.listingId
					);
					// console.log({storedListing});
					expect(storedListing[0]).to.be.equal(listing.listingId);
				});
				it("revert because invalid listing type", async function () {
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					// @ts-ignore
					await expect(
						hardHatMarketplace.createListing(
							listing.listingId,
							ethers.ZeroAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							listing.active
						)
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"InvalidListingType"
					);
				});

				it("revert because not token owner", async function () {
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					// @ts-ignore
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.createListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								listing.pricePer,
								listing.royaltyBasePoints,
								listing.active
							)
					).to.be.revertedWithCustomError(hardHatMarketplace, "NotTokenOwner");
				});

				it("revert because approval not set for marketplace contract", async function () {
					await hardHatAvatar
						.connect(addr1)
						.setApprovalForAll(await hardHatMarketplace.getAddress(), false);
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					// @ts-ignore
					await expect(
						hardHatMarketplace
							.connect(addr1)
							.createListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								listing.pricePer,
								listing.royaltyBasePoints,
								listing.active
							)
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"ApprovalNotSetForMarketplace"
					);
				});

				it("revert because listing prices is 0", async function () {
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					// @ts-ignore
					await expect(
						hardHatMarketplace
							.connect(addr1)
							.createListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								0,
								listing.royaltyBasePoints,
								listing.active
							)
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"CreateListingFailed"
					);
				});

				it("revert because token already listed", async function () {
					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					await hardHatMarketplace
						.connect(addr1)
						.createListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							listing.active
						);

					// @ts-ignore
					await expect(
						hardHatMarketplace
							.connect(addr1)
							.createListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								listing.pricePer,
								listing.royaltyBasePoints,
								listing.active
							)
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"CreateListingFailed"
					);
				});

				it("revert because listing type is not active", async function () {
					const listingType = {
						contractAddress: await hardHatAvatar.getAddress(),
						description: "avatar",
						ercStandard: 721,
						active: false,
						valid: true,
					};

					// @ts-ignore
					await hardHatMarketplace.setListingType(listingType);

					await hardHatAvatar.getAddress(), "avatar", 721, true, true;

					const listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					// @ts-ignore
					await expect(
						hardHatMarketplace
							.connect(addr1)
							.createListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								listing.pricePer,
								listing.royaltyBasePoints,
								listing.active
							)
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"InactiveListingType"
					);
				});
			});

			describe("updateListing", function () {
				let listing: ListingStruct;
				beforeEach(async function () {
					listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					await hardHatMarketplace
						.connect(addr1)
						.createListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							listing.active
						);
				});

				it("success", async function () {
					await hardHatMarketplace
						.connect(addr1)
						.updateListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							false
						);

					const storedListing = await hardHatMarketplace.getListing(
						listing.listingId
					);
					expect(storedListing.active).to.be.false;
				});

				it("revert because msg.sender is not listing seller", async function () {
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.updateListing(
								listing.listingId,
								listing.listingAddress,
								listing.tokenId,
								listing.numListed,
								listing.pricePer,
								listing.royaltyBasePoints,
								false
							)
					).to.be.revertedWith("INV_UPDATE_REQUEST");
				});
			});

			describe("purchaseListingStoredOnContract", function () {
				let listing: ListingStruct;
				beforeEach(async function () {
					listing = await getListingStruct(
						ethers.encodeBytes32String(listingId)
					);
					// console.log({listing});
					await hardHatMarketplace
						.connect(addr1)
						.createListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							listing.active
						);
				});

				it("success", async function () {
					await hardHatMarketplace
						.connect(addr2)
						.purchaseListingStoredOnContract(listing.listingId, 1, {
							value: listing.pricePer,
						});
					const tokenOwner = await hardHatAvatar.ownerOf(listing.tokenId);
					expect(tokenOwner).to.be.equal(addr2.address);

					const listingIds = await hardHatMarketplace.getActiveListingIds();
					// @ts-ignore
					expect(listingIds.indexOf(listing.listingId)).to.be.equal(-1);

					const tokens = await hardHatMarketplace.getTokensListedForListing(
						listing.listingAddress
					);
					// @ts-ignore
					expect(tokens.indexOf(listing.tokenId)).to.be.equal(-1);

					const purchases = await hardHatMarketplace.getPurchasesByAddress(
						addr2.address
					);
					expect(purchases.length).to.be.equal(1);

					// @ts-ignore
					const storedListing = await hardHatMarketplace.getListing(
						listing.listingId
					);
					expect(storedListing.buyer).to.be.equal(addr2.address);
				});

				it("reverted because buyer is seller", async function () {
					await expect(
						hardHatMarketplace
							.connect(addr1)
							.purchaseListingStoredOnContract(listing.listingId, 1, {
								value: listing.pricePer,
							})
					).to.be.revertedWith("BUYER_SELLER_MATCH");
				});

				it("reverted because listing is not active", async function () {
					await hardHatMarketplace
						.connect(addr1)
						.updateListing(
							listing.listingId,
							listing.listingAddress,
							listing.tokenId,
							listing.numListed,
							listing.pricePer,
							listing.royaltyBasePoints,
							false
						);

					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOnContract(listing.listingId, 1, {
								value: listing.pricePer,
							})
					).to.be.revertedWithCustomError(hardHatMarketplace, "InvalidListing");
				});

				it("reverted because listing is not valid", async function () {
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOnContract(
								ethers.encodeBytes32String(uid.rnd()),
								1,
								{ value: listing.pricePer }
							)
					).to.be.revertedWithCustomError(hardHatMarketplace, "InvalidListing");
				});

				it("reverted because item(s) already sold", async function () {
					await hardHatMarketplace
						.connect(addr2)
						.purchaseListingStoredOnContract(listing.listingId, 1, {
							value: listing.pricePer,
						});

					await expect(
						hardHatMarketplace
							.connect(addr3)
							.purchaseListingStoredOnContract(listing.listingId, 1, {
								value: listing.pricePer,
							})
					).to.be.revertedWithCustomError(hardHatMarketplace, "InvalidListing");
				});
			});

			describe("purchaseListingStoredOffContract", function () {
				let listing: ListingStruct;
				const getArguments = async (
					signer = addr1
				): Promise<[ListingStruct, number, string, string]> => {
					// console.log({listingId});
					const listIdInBytes = ethers.encodeBytes32String(listingId);

					listing = await getListingStruct(listIdInBytes);

					const message = `Listing: ${listIdInBytes}`;

					const dataHash = ethers.keccak256(ethers.toUtf8Bytes(message));
					const dataHashBin = ethers.getBytes(dataHash);

					// const packed = ethers.solidityPack(["string"], [message]);
					// const signature = ethers.keccak256(packed);
					const signature = await signer.signMessage(dataHashBin);
					return [listing, 1, message, signature];
				};
				type Arguments = [
					_listing: ListingStruct,
					_quantity: BigNumberish,
					_message: string,
					_signature: BytesLike
				];
				const purchaseListing = async (args: Arguments) => {
					await hardHatMarketplace
						.connect(addr2)
						.purchaseListingStoredOffContract(...args, { value: pricePer });
				};

				it("successful listing purchase", async function () {
					await purchaseListing(await getArguments());
					const owner = await hardHatAvatar.ownerOf(soldTokenId);
					// console.log({owner, addr2: addr2.address});
					expect(owner).to.be.equal(addr2.address);

					const listingIds = await hardHatMarketplace.getActiveListingIds();
					// @ts-ignore
					expect(listingIds.indexOf(listing.listingId)).to.be.equal(-1);

					const tokens = await hardHatMarketplace.getTokensListedForListing(
						listing.listingAddress
					);
					// @ts-ignore
					expect(tokens.indexOf(listing.tokenId)).to.be.equal(-1);
				});

				it("reverts because listing already purchased", async function () {
					const args = await getArguments();
					await purchaseListing(args);
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOffContract(...args, { value: pricePer })
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"ListingAlreadyPurchased"
					);
				});

				it("reverts because message not signed by seller", async function () {
					const args = await getArguments(addr3);
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOffContract(...args, { value: pricePer })
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"InvalidSignature"
					);
				});

				it("reverts because seller does not own token", async function () {
					await hardHatAvatar
						.connect(addr1)
						.transferFrom(addr1.address, addr3.address, soldTokenId);
					const args = await getArguments();
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOffContract(...args, { value: pricePer })
					).to.be.revertedWithCustomError(hardHatMarketplace, "NotTokenOwner");
				});

				it("reverts because isApprovedForAll false for marketplace contract", async function () {
					await hardHatAvatar
						.connect(addr1)
						.setApprovalForAll(await hardHatMarketplace.getAddress(), false);
					const args = await getArguments();
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOffContract(...args, { value: pricePer })
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"ApprovalNotSetForMarketplace"
					);
				});

				it("reverts because incorrect payment amount sent", async function () {
					const args = await getArguments();
					await expect(
						hardHatMarketplace
							.connect(addr2)
							.purchaseListingStoredOffContract(...args, {
								value: ethers.parseEther("0.00001"),
							})
					).to.be.revertedWithCustomError(
						hardHatMarketplace,
						"InvalidIntValue"
					);
				});

				it("royalty amount ((pricePer * royaltyBasePoints) / 10000) sent to royalty receiver", async function () {
					const receiverBalance = await getBalance(owner.address);
					const royaltyAmt =
						(pricePer * BigInt(royaltyBasePoints)) / BigInt(10000);

					await purchaseListing(await getArguments());
					const newReceiverBalance = await getBalance(owner.address);
					expect(newReceiverBalance).to.be.equal(receiverBalance + royaltyAmt);
				});

				it("final sale amount ((pricePer * numList) - royaltyAmt) sent to seller", async function () {
					const sellerBalance = await getBalance(addr1.address);
					const royaltyAmt =
						(pricePer * BigInt(royaltyBasePoints)) / BigInt(10000);

					const finalPurchaseAmt = pricePer - royaltyAmt;
					await purchaseListing(await getArguments());
					const newReceiverBalance = await getBalance(addr1.address);
					expect(newReceiverBalance).to.be.equal(
						sellerBalance + finalPurchaseAmt
					);
				});
			});
		});
	});
});
