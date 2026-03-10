import { ethers, deployments } from "hardhat";
import { expect } from "chai";
import SilksMinterSDK, { MintParams } from "../sdk/minter";
import { Signer } from "ethers";
import { deploy } from "../scripts/deployDiamond";
import {
	impersonateAccount,
	loadFixture,
	time,
} from "@nomicfoundation/hardhat-network-helpers";
import { marketplace } from "../typechain-types/contracts/facets";
import { deployDiamondFixture } from "./fixtures/deployDiamondFixture";
import { deployWithPacks } from "./fixtures/deployDiamondFixtureWithPacks";

describe("PackFacet Tests", function () {
	describe("Purchase functionality", function () {
		this.beforeEach(async function () {
			// console.log("Before each 1");
		});

		it("Pack tests", async function () {
			const {
				owner,
				addr1,
				marketplaceContract,
				avatarContractAddress,
				avatarContract,
				horseV2Contract,
				avatarPrice,
			} = await loadFixture(deployWithPacks);

			console.log("Before pack mint");
			// Check that addr1 has 0 avatars
			let avatarCount = await avatarContract.balanceOf(addr1.address);
			console.log("avatarCount: ", avatarCount);
			expect(avatarCount).to.equal(0);
			// Check that addr1 has 0 horses
			let horseCount = await horseV2Contract.balanceOf(addr1.address);
			console.log("horseCount: ", horseCount);
			expect(horseCount).to.equal(0);

			const packId = 0;
			const quantity = 2;
			const value = 200;
			console.log("About to mint: ", {
				packId,
				quantity,
				value,
			});

			const pack = await marketplaceContract
				.connect(addr1)
				.purchasePack(packId, quantity, {
					value,
				});

			console.log("After pack mint");
			// Check that addr1 now owns two of each
			avatarCount = await avatarContract.balanceOf(addr1.address);
			console.log("avatarCount: ", avatarCount);
			expect(avatarCount).to.equal(4);
			// Check that addr1 has 0 horses
			horseCount = await horseV2Contract.balanceOf(addr1.address);
			console.log("horseCount: ", horseCount);
			expect(horseCount).to.equal(4);

			// Try to mint without value and expect it to revert
			await expect(
				marketplaceContract.connect(addr1).purchasePack(packId, quantity, {
					value: 99,
				})
			)
				.to.be.revertedWithCustomError(marketplaceContract, "InvalidEthTotal")
				.withArgs(99, 200);
		});
	});
});
