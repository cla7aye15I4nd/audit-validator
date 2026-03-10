import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import SilksMinterSDK, { MintParams } from "../sdk/minter";
import { Signer } from "ethers";
import { deploy } from "../scripts/deployDiamond";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { marketplace } from "../typechain-types/contracts/facets";

describe("SilksMinterFacet Tests", function () {
	async function deployDiamondFixture() {
		const [owner, addr1, addr2] = await ethers.getSigners(); // ...addrs
		const marketplaceContractAddress = await deploy();
		const marketplaceContract = await ethers.getContractAt(
			"MarketplaceDiamondABI",
			marketplaceContractAddress,
			owner
		);

		// Avatar Contract on Goerli: 0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c
		// Owner of Avatar: 0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6
		const avatarContract = await ethers.getContractAt(
			"IAvatarNFT",
			"0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c",
			owner
		);

		// HorseV2 Contract on Goerli:
		// 0xa98262A0D8Eb404AD33178c9bE792C276BD0d22F
		// Owner of HorseV2: 0x4a40E425a8D1EE6279f860d8fd5db3D3661558d6
		const horseV2Contract = await ethers.getContractAt(
			"IHorseNFT",
			"0xa98262A0D8Eb404AD33178c9bE792C276BD0d22F",
			owner
		);

		const silksMinterContractAddress = marketplaceContractAddress;
		const avatarContractAddress = "0xde3d8dee91e08a4b0c54b1e93a20ffe079c6628c"; // Avatar Address on Goerli
		const horseV2ContractAddress = "0xa98262A0D8Eb404AD33178c9bE792C276BD0d22F"; // HorseV2 Contract on Goerli

		// Initialize SDK
		const sdk = new SilksMinterSDK({
			providerOrSigner: owner, // Signer with which you want to interact with the contract
			silksMinterContractAddress,
			avatarContractAddress,
			horseV2ContractAddress,
		});

		return {
			owner,
			addr1,
			addr2,
			marketplaceContract,
			sdk,
			avatarContract,
			horseV2Contract,
		};
	}

	describe("Admin functionality", function () {
		it("Should allow MINTER_ADMIN_ROLE to add the Avatar Contract", async function () {
			const { owner, addr1, addr2, marketplaceContract, sdk, avatarContract } =
				await loadFixture(deployDiamondFixture);

			const avatarContractAddress = ethers.getAddress(
				await avatarContract.getAddress()
			);

			await marketplaceContract.addContract(
				avatarContractAddress,
				"function mint(address,count)",
				0,
				false,
				[{ tier: 0, price: 100 }]
			);

			const contractsData = await marketplaceContract.getContracts();
			console.log({ contractsData });

			expect(contractsData[0].contractAddress).to.equal(avatarContractAddress);
			expect(contractsData.length).to.equal(1);
		});

		it("Should NOT allow non-MINTER_ADMIN_ROLES add the Avatar Contract", async function () {
			const { owner, addr1, addr2, marketplaceContract, sdk, avatarContract } =
				await loadFixture(deployDiamondFixture);

			const avatarContractAddress = await avatarContract.getAddress();
			expect(
				marketplaceContract
					.connect(addr1)
					.addContract(
						avatarContractAddress,
						"function mint(address,count)",
						0,
						false,
						[{ tier: 0, price: 100 }]
					)
			).to.be.reverted;

			const contractsData = await marketplaceContract.getContracts();
			console.log({ contractsData });

			expect(contractsData.length).to.equal(0);
		});
	});
});
