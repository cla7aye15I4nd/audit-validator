import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployDiamondFixture } from "./deployDiamondFixture";
import { expect } from "chai";

export async function deployWithDiscount() {
	const { owner, marketplaceContract, avatarContract, ...args } =
		await loadFixture(deployDiamondFixture);

	// Unix Timestamp of Feburary 1st, 2024 (1 week before blockchain fork)
	const feb012024 = new Date("2024-02-01T00:00:00Z");
	const feb012024Timestamp = Math.floor(feb012024.getTime() / 1000);

	// Unix Timestamp of Feburary 28th, 2024
	const feb282024 = new Date("2024-02-28T00:00:00Z");
	const feb282024Timestamp = Math.floor(feb282024.getTime() / 1000);

	const avatarTotalCount = await avatarContract.totalSupply();
	await marketplaceContract.connect(owner).addDiscount(
		10n, // 10% discount
		feb012024Timestamp, // Feb 1st, 2024
		feb282024Timestamp, // Feb 28th, 2024
		0n, // Start ID
		avatarTotalCount + 2n, // End ID,
		2024
	);

	const currentDiscounts = await marketplaceContract.getActiveDiscountIds(2024);

	const currentDiscounts2 = await marketplaceContract.getDiscount(0, 2024);

	expect(await marketplaceContract.getActiveDiscountCount(2024)).to.be.equals(
		1n
	);

	return {
		owner,
		marketplaceContract,
		avatarContract,
		...args,
	};
}

export const deployWith2Discounts = async () => {
	const { owner, marketplaceContract, avatarContract, ...args } =
		await loadFixture(deployWithDiscount);

	// Create discount for avatar tokens 3700-3800 that's valid from February
	// 15th, 2024 to February 28th, 2024 and gives 10 percent off
	const feb202024 = new Date("2024-02-20T00:00:00Z");
	const feb202024Timestamp = Math.floor(feb202024.getTime() / 1000);

	const feb282024 = new Date("2024-02-28T00:00:00Z");
	const feb282024Timestamp = Math.floor(feb282024.getTime() / 1000);
	const avatarTotalCount = await avatarContract.totalSupply();
	await marketplaceContract.connect(owner).addDiscount(
		10n, // 10% discount
		feb202024Timestamp, // Feb 15th, 2024
		feb282024Timestamp, // Feb 28th, 2024
		avatarTotalCount + 3n, // Start ID
		avatarTotalCount + 103n, // End ID,
		2024
	);

	const currentDiscounts = await marketplaceContract.getActiveDiscountIds(2024);
	expect(await marketplaceContract.getActiveDiscountCount(2024)).to.be.equals(
		1n
	);

	return {
		owner,
		marketplaceContract,
		avatarContract,
		...args,
	};
};

export const deployWith4Discounts = async () => {
	const { owner, marketplaceContract, ...args } = await loadFixture(
		deployWith2Discounts
	);

	// Unix Timestamp of Feburary 1st, 2024 (1 week before blockchain fork)
	const feb012025 = new Date("2024-02-01T00:00:00Z");
	const feb012025Timestamp = Math.floor(feb012025.getTime() / 1000);

	// Unix Timestamp of Feburary 15th, 2024
	const feb152025 = new Date("2024-02-15T00:00:00Z");
	const feb152025Timestamp = Math.floor(feb152025.getTime() / 1000);

	const feb282025 = new Date("2025-02-28T00:00:00Z");
	const feb282025Timestamp = Math.floor(feb282025.getTime() / 1000);

	await marketplaceContract.connect(owner).addDiscount(
		10n, // 10% discount
		feb012025Timestamp, // Feb 15th, 2024
		feb282025Timestamp, // Feb 28th, 2024
		0n, // Start ID
		3700n, // End ID
		2025
	);

	await marketplaceContract.connect(owner).addDiscount(
		10n, // 10% discount
		feb152025Timestamp, // Feb 15th, 2024
		feb282025Timestamp, // Feb 28th, 2024
		3701n, // Start ID
		3800n, // End ID
		2025
	);

	return {
		owner,
		marketplaceContract,
		...args,
	};
};
