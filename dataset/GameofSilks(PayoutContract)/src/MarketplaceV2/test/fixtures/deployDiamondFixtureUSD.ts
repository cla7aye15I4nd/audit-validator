import { ethers } from "hardhat";
import { deploy } from "../../scripts/deployDiamond";
import SilksMinterSDK from "../../sdk/minter";

export async function deployDiamondFixture() {
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
		"0xde3d8DEE91E08A4b0c54b1E93A20ffE079C6628C",
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
	const avatarContractAddress = "0xde3d8DEE91E08A4b0c54b1E93A20ffE079C6628C"; // Avatar Address on Goerli
	const horseV2ContractAddress = "0xa98262A0D8Eb404AD33178c9bE792C276BD0d22F"; // HorseV2 Contract on Goerli

	const avatarPrice = 50_00; // 50 USD
	const horseV2Price = 200_00; // 200 USD

	await marketplaceContract.addContract(
		avatarContractAddress,
		"mint(address,uint256)",
		0,
		true,
		[{ tier: 0, price: avatarPrice }]
	);
	await marketplaceContract.addContract(
		horseV2ContractAddress,
		"externalMint(uint256,uint256,uint256,address)",
		2,
		true,
		[{ tier: 1, price: horseV2Price }]
	);

	// Tell Avatar Contract that the Marketplace is allowed to mint (make it
	// owner)
	const targetAddress = "0xE1c689334186473DB5027b5f9354596CCEe54669"; // Address you want to impersonate, owner of Avatar on Goerli
	await ethers.provider.send("hardhat_impersonateAccount", [targetAddress]);
	const impersonatedSigner = await ethers.getSigner(targetAddress);

	await avatarContract
		.connect(impersonatedSigner)
		.transferOwnership(marketplaceContractAddress);

	const targetAddress2 = "0x4Ab88E00570B740c1C403034D05954584d6351d1"; // Address you want to impersonate, owner of Avatar on Mainnet
	await ethers.provider.send("hardhat_impersonateAccount", [targetAddress2]);
	const impersonatedSigner2 = await ethers.getSigner(targetAddress2);

	await horseV2Contract
		.connect(impersonatedSigner2)
		.allowExternalMintAddress(marketplaceContractAddress);

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
		avatarContractAddress,
		horseV2ContractAddress,
		avatarPrice,
		horseV2Price,
	};
}
