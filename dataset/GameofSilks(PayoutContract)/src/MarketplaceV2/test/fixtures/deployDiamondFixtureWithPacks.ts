import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployDiamondFixture } from "./deployDiamondFixture";
import { expect } from "chai";

// @ts-expect-error This is fine.
BigInt.prototype.toJSON = function () {
	const int = Number.parseInt(this.toString());
	return int ?? this.toString();
};

export async function deployWithPacks() {
	const {
		owner,
		marketplaceContract,
		avatarContractAddress,
		horseV2ContractAddress,
		...args
	} = await loadFixture(deployDiamondFixture);

	// // Unix Timestamp of Feburary 1st, 2024 (1 week before blockchain fork)
	// const feb012024 = new Date("2024-02-01T00:00:00Z");
	// const feb012024Timestamp = Math.floor(feb012024.getTime() / 1000);

	// // Unix Timestamp of Feburary 15th, 2024
	// const feb282024 = new Date("2024-02-28T00:00:00Z");
	// const feb282024Timestamp = Math.floor(feb282024.getTime() / 1000);

	await marketplaceContract.connect(owner).addPack(
		[
			{
				amount: 2n,
				assetAddress: avatarContractAddress, // avatar contract address
				assetType: 0n,
				seasonId: 0n,
				payoutTier: 0n,
			},
			{
				amount: 2n,
				assetAddress: horseV2ContractAddress, // horse contract address
				assetType: 2n,
				seasonId: 2024n,
				payoutTier: 1n,
			},
		],
		100n, // pricePerPack
		2n, // maxPurchasePerTx
		true // isActive
	);

	const packs = await marketplaceContract.getActivePacks();
	console.log("packs: ", JSON.stringify(packs, null, 2));

	// expect(packs.length).to.equal(1);

	return {
		owner,
		marketplaceContract,
		avatarContractAddress,
		horseV2ContractAddress,
		...args,
	};
}
