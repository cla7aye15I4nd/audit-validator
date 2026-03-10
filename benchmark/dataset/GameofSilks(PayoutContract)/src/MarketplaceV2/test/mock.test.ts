import { BigNumberish, Contract, ContractFactory, Signer } from "ethers";
import { ethers } from "hardhat";
import {
	MarketplaceMock as MarketplaceMock,
	MarketplaceMock__factory,
	MockNFT,
	MockNFT__factory,
} from "../typechain-types";
import { expect } from "chai";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Marketplace Contract", function () {
	let Marketplace: MarketplaceMock__factory;
	let marketplace: MarketplaceMock;
	let nftContract: MockNFT;
	let owner: SignerWithAddress;
	let seller: SignerWithAddress;
	let buyer: SignerWithAddress;
	let listing: {
		seller: string;
		tokenId: number;
		price: BigNumberish;
		tokenAddress: string;
		listingId: string;
	};
	let signature: string;
	const tokenId = 1;
	const price = ethers.parseEther("1"); // 1 ETH
	const royaltyAmount = ethers.parseEther("0.1"); // 0.1 ETH

	before(async function () {
		[owner, seller, buyer] = await ethers.getSigners();

		// Deploy an ERC721 token for testing
		const NFT = (await ethers.getContractFactory(
			"MockNFT"
		)) as unknown as MockNFT__factory;
		nftContract = await NFT.deploy("TestNFT", "TNFT", "baseURI/");
		await nftContract.waitForDeployment();

		// Grant the minter role to the seller
		const minterRole = await nftContract.MINTER_ROLE();
		await nftContract.grantRole(minterRole, seller.address);

		// Mint a token to the seller for testing
		await nftContract.connect(seller).mint(seller.address);

		console.log("Minting initial token to seller");
		await nftContract.connect(seller).mint(seller.address);

		// // Deploy an ERC721 token for testing
		// const NFT = (await ethers.getContractFactory(
		// 	"MockNFT"
		// )) as unknown as MockNFT__factory;
		// nftContract = await NFT.deploy("TestNFT", "TNFT", "baseURI/");
		// await nftContract.waitForDeployment();

		// Mint a token to the seller for testing
		// await nftContract.connect(seller).mint(await seller.getAddress());

		// Deploy the Marketplace contract
		Marketplace = (await ethers.getContractFactory(
			"MarketplaceMock"
		)) as unknown as MarketplaceMock__factory;
		marketplace = await Marketplace.deploy(
			await owner.getAddress(),
			await nftContract.getAddress()
		);

		console.log("Granting marketplace seller rights");
		await nftContract
			.connect(seller)
			.setApprovalForAll(await marketplace.getAddress(), true);
		await marketplace.waitForDeployment();

		// Create a listing object
		listing = {
			seller: await seller.getAddress(),
			tokenId: tokenId,
			price: price,
			tokenAddress: await nftContract.getAddress(),
			listingId: ethers.keccak256(ethers.toUtf8Bytes("1")), // Mock listing ID
		};

		// Seller signs the message
		const messageHash = ethers.solidityPackedKeccak256(
			["address", "uint256", "uint256", "address", "bytes32"],
			[
				listing.seller,
				listing.tokenId,
				listing.price,
				listing.tokenAddress,
				listing.listingId,
			]
		);
		signature = await seller.signMessage(ethers.getBytes(messageHash));
	});

	it("Should process a listing purchase and transfer funds and NFT correctly", async function () {
		// Buyer sends ETH to purchase the NFT
		console.log("Starting test");
		console.log("calling purchaseListing");
		const transactionResponse = await marketplace
			.connect(buyer)
			.purchaseListing(listing, signature, royaltyAmount, {
				value: listing.price,
			});

		console.log("Calling transacionResponse");
		// Check gas usage
		const transactionReceipt = await transactionResponse.wait();
		console.log(`Gas used: ${transactionReceipt?.gasUsed.toString()}`);

		// Check balances and ownership
		expect(await nftContract.ownerOf(tokenId)).to.equal(
			await buyer.getAddress()
		);
		// Add other checks as necessary
	});
});
