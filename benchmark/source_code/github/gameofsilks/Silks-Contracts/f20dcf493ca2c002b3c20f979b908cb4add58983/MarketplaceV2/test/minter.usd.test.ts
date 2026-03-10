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
import { deployDiamondFixture } from "./fixtures/deployDiamondFixtureUSD";
import {
	deployWith2Discounts,
	deployWith4Discounts,
	deployWithDiscount,
} from "./fixtures/deployDiamondFixtureWithDiscounts";

describe("SilksMinterFacet Tests", function () {
	describe("Minting functionality", function () {
		this.beforeEach(async function () {});
		it("Should to mint Avatar successfully using SDK", async function () {
			const {
				owner,
				marketplaceContract,
				avatarContractAddress,
				avatarContract,
				avatarPrice,
			} = await loadFixture(deployDiamondFixture);

			const params: MintParams = {
				to: owner.address,
				quantity: 1,
				seasonId: 0,
				payoutTier: 0,
			};
			const additionalPayload = "0x"; // Assuming no additional payload is needed for avatars
			const avatarIds: number[] = []; // Assuming no avatar IDs needed for minting avatars

			await marketplaceContract
				.connect(owner)
				.mint(avatarContractAddress, params, additionalPayload, avatarIds, {
					value: avatarPrice,
				});

			console.log(`Sending ${avatarPrice - 1} and expecting to revert`);
			await expect(
				marketplaceContract
					.connect(owner)
					.mint(avatarContractAddress, params, additionalPayload, avatarIds, {
						value: avatarPrice - 1,
					})
			).to.be.revertedWithCustomError(marketplaceContract, "InsufficientFunds");

			expect(await avatarContract.balanceOf(owner.address)).to.equal(1);
		});

		it("Should to mint HorseV2 successfully", async function () {
			const {
				owner,
				addr1,
				marketplaceContract,
				horseV2Contract,
				horseV2ContractAddress,
				horseV2Price,
			} = await loadFixture(deployDiamondFixture);

			const params: MintParams = {
				to: addr1.address,
				quantity: 1,
				seasonId: 2024,
				payoutTier: 1,
			};
			const additionalPayload = "0x"; // Assuming no additional payload is needed for avatars
			const avatarIds: number[] = []; // Assuming no avatar IDs needed for minting avatars

			await marketplaceContract
				.connect(addr1)
				.mint(horseV2ContractAddress, params, additionalPayload, avatarIds, {
					value: horseV2Price, // Sending 1 Ether, for example
				});

			await expect(
				marketplaceContract
					.connect(addr1)
					.mint(horseV2ContractAddress, params, additionalPayload, avatarIds, {
						value: horseV2Price - 1, // Sending 1 Ether, for example
					})
			).to.be.revertedWithCustomError(marketplaceContract, "InsufficientFunds");

			expect(await horseV2Contract.balanceOf(addr1.address)).to.equal(1);
		});

		describe("With discounts", function () {
			it("Should allow user to mint Avatar with discount (original price)", async function () {
				const {
					owner,
					marketplaceContract,
					avatarContractAddress,
					avatarContract,
					avatarPrice,
				} = await loadFixture(deployWithDiscount);
				expect(
					await marketplaceContract.getActiveDiscountCount(2024)
				).to.be.equals(1n);
				const params: MintParams = {
					to: owner.address,
					quantity: 1,
					seasonId: 0,
					payoutTier: 0,
				};
				const additionalPayload = "0x"; // Assuming no additional payload is needed for avatars
				const avatarIds: number[] = [0]; // Assuming no avatar IDs needed for minting avatars
				await marketplaceContract
					.connect(owner)
					.mint(avatarContractAddress, params, additionalPayload, avatarIds, {
						value: avatarPrice,
					});
				await expect(
					marketplaceContract
						.connect(owner)
						.mint(avatarContractAddress, params, additionalPayload, avatarIds, {
							value: avatarPrice - 1,
						})
				).to.be.revertedWithCustomError(
					marketplaceContract,
					"InsufficientFunds"
				);
				expect(await avatarContract.balanceOf(owner.address)).to.equal(1);
			});
			it("Should should revert if you pass in Avatars you don't own (discounted price)", async function () {
				const {
					owner,
					marketplaceContract,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
				} = await loadFixture(deployWithDiscount);
				expect(
					await marketplaceContract.getActiveDiscountCount(2024)
				).to.be.equals(1n);
				const additionalPayload = "0x"; // Assuming no additional payload is needed for avatars
				await marketplaceContract.connect(owner).mint(
					avatarContractAddress,
					{
						to: owner.address,
						quantity: 2,
						seasonId: 0,
						payoutTier: 0,
					},
					additionalPayload,
					[], // AvatarIDs
					{
						value: avatarPrice * 2,
					}
				);
				const avatarTotalCount = await avatarContract.totalSupply();

				expect(await avatarContract.balanceOf(owner.address)).to.equal(2);
				expect(await avatarContract.ownerOf(avatarTotalCount)).to.equal(
					owner.address
				);
				expect(await avatarContract.ownerOf(avatarTotalCount - 1n)).to.equal(
					owner.address
				);
			});
			it("Should allow user to mint HorseV2 with discount (discounted price)", async function () {
				const {
					addr1,
					marketplaceContract,
					horseV2Contract,
					horseV2ContractAddress,
					horseV2Price,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
				} = await loadFixture(deployWithDiscount);

				expect(
					await marketplaceContract.getActiveDiscountCount(2024)
				).to.be.equals(1n);
				const additionalPayload = "0x"; // Assuming no additional payload is needed for avatars

				// Buy 2 Avatars
				await marketplaceContract.connect(addr1).mint(
					avatarContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 0,
						payoutTier: 0,
					},
					additionalPayload,
					[], // AvatarIDs
					{
						value: avatarPrice * 2,
					}
				);
				const avatarTotalCount = await avatarContract.totalSupply();
				expect(await avatarContract.balanceOf(addr1.address)).to.equal(2);
				expect(await avatarContract.ownerOf(avatarTotalCount)).to.equal(
					addr1.address
				);
				expect(await avatarContract.ownerOf(avatarTotalCount - 1n)).to.equal(
					addr1.address
				);

				console.log(
					"avatarTotalCount, avatarTotalCount - 1n:",
					avatarTotalCount,
					avatarTotalCount - 1n
				);
				await marketplaceContract.connect(addr1).mint(
					horseV2ContractAddress,
					{
						to: addr1.address,
						quantity: 1,
						seasonId: 2024,
						payoutTier: 1,
					},
					additionalPayload,
					[avatarTotalCount, avatarTotalCount - 1n], // AvatarIDs
					{
						value: horseV2Price * 0.9, // Sending 1 Ether, for example
					}
				);

				await expect(
					marketplaceContract.connect(addr1).mint(
						horseV2ContractAddress,
						{
							to: addr1.address,
							quantity: 1,
							seasonId: 2024,
							payoutTier: 1,
						},
						additionalPayload,
						[avatarTotalCount, avatarTotalCount - 1n], // AvatarIDs
						{
							value: 0, // Sending 1 Ether, for example
						}
					)
				).to.be.revertedWithCustomError(
					marketplaceContract,
					"InsufficientFunds"
				);
				expect(await horseV2Contract.balanceOf(addr1.address)).to.equal(1);
			});

			it("Should allow 2 set's of discounts", async () => {
				const {
					addr1,
					addr2,
					marketplaceContract,
					horseV2Contract,
					horseV2ContractAddress,
					horseV2Price,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
				} = await loadFixture(deployWith2Discounts);

				// Mint 2 avatars for addr1
				await marketplaceContract.connect(addr1).mint(
					avatarContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 0,
						payoutTier: 0,
					},
					"0x",
					[], // AvatarIDs
					{
						value: avatarPrice * 2,
					}
				);

				// Mint 2 avatars for addr2
				await marketplaceContract.connect(addr2).mint(
					avatarContractAddress,
					{
						to: addr2.address,
						quantity: 2,
						seasonId: 0,
						payoutTier: 0,
					},
					"0x",
					[], // AvatarIDs
					{
						value: avatarPrice * 2,
					}
				);

				// Addr AvatarTokenIds should be AvatarContracct.totalSupply()
				// and AvatarContracct.totalSupply() - 1, make an array of his
				// and then make one for addr1 and the two before that
				const avatarTotalCount = await avatarContract.totalSupply();
				const addr1AvatarIds = [avatarTotalCount - 2n, avatarTotalCount - 3n];
				const addr2AvatarIds = [avatarTotalCount, avatarTotalCount - 1n];

				const discountReturn = await marketplaceContract
					.connect(addr1)
					.getDiscountsForAvatars(addr1AvatarIds, 2024);

				const allDiscounts = await marketplaceContract.getActiveDiscounts(2024);

				// Mint 1 horseV2 for addr1
				await marketplaceContract.connect(addr1).mint(
					horseV2ContractAddress,
					{
						to: addr1.address,
						quantity: 1,
						seasonId: 2024,
						payoutTier: 1,
					},
					"0x",
					addr1AvatarIds,
					{
						value: horseV2Price * 0.9, // Sending 1 Ether, for example
					}
				);

				const discountReturn2 = await marketplaceContract
					.connect(addr1)
					.getDiscountsForAvatars(addr1AvatarIds, 2024);

				// Try to mint one at discounted price for addr2 but it should
				// revert
				await expect(
					marketplaceContract.connect(addr2).mint(
						horseV2ContractAddress,
						{
							to: addr2.address,
							quantity: 1,
							seasonId: 2024,
							payoutTier: 1,
						},
						"0x",
						addr2AvatarIds,
						{
							value: horseV2Price * 0.9, // Sending 1 Ether, for example
						}
					)
				).to.be.revertedWithCustomError(
					marketplaceContract,
					"InsufficientFunds"
				);

				// Unix Timestamp for Feb 15th, 2024
				const feb222024 = new Date("2024-02-22T00:00:00Z");
				const feb222024Timestamp = Math.floor(feb222024.getTime() / 1000);

				// Fast forward to that timestamp
				await time.increaseTo(feb222024Timestamp);

				// Get current discounts again
				const currentDiscounts = await marketplaceContract.getActiveDiscountIds(
					2024
				);

				// Retry minting for addr2
				await marketplaceContract.connect(addr2).mint(
					horseV2ContractAddress,
					{
						to: addr2.address,
						quantity: 1,
						seasonId: 2024,
						payoutTier: 1,
					},
					"0x",
					addr2AvatarIds,
					{
						value: horseV2Price * 0.9, // Sending 1 Ether, for example
					}
				);
			});

			it("Should only allow non-avatar owners to mint regularly", async () => {
				const {
					addr1,
					marketplaceContract,
					horseV2Contract,
					horseV2ContractAddress,
					horseV2Price,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
				} = await loadFixture(deployWithDiscount);
				// Verify that addr1 owns 0 avatars
				const avatarCount = await avatarContract.balanceOf(addr1.address);
				expect(avatarCount).to.equal(0);

				// Mint 2 HorseV2 for addr1
				await marketplaceContract.connect(addr1).mint(
					horseV2ContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 2024,
						payoutTier: 1,
					},
					"0x",
					[], // AvatarIDs
					{
						value: horseV2Price * 2,
					}
				);
			});

			it("Should only allow avatar owners to mint if exclusion is set", async () => {
				const {
					addr1,
					marketplaceContract,
					horseV2Contract,
					horseV2ContractAddress,
					horseV2Price,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
					owner,
				} = await loadFixture(deployWithDiscount);
				// Verify that addr1 owns 0 avatars
				const avatarCount = await avatarContract.balanceOf(addr1.address);
				expect(avatarCount).to.equal(0);

				// Unix timestamp for now
				// const now = Math.floor(Date.now() / 1000);
				// Unix timstamp for 1 week ago
				const now = Math.floor(Date.now() / 1000);
				const lastWeek = now - 60 * 60 * 24 * 7;

				// Unix timstamp for 1 week from now
				const nextWeek = now + 60 * 60 * 24 * 7;

				// Set mint exclusion on for now till 1 week from now
				await marketplaceContract
					.connect(owner)
					.updateMintExclusion(true, lastWeek, nextWeek);

				// Mint 2 HorseV2 for addr1
				await expect(
					marketplaceContract.connect(addr1).mint(
						horseV2ContractAddress,
						{
							to: addr1.address,
							quantity: 2,
							seasonId: 2024,
							payoutTier: 1,
						},
						"0x",
						[], // AvatarIDs
						{
							value: horseV2Price * 2,
						}
					)
				).to.revertedWithCustomError(
					marketplaceContract,
					"MintExlusiveToAvatarHolders"
				);

				// Fast forward hardhat network to 1 week from now
				await time.increaseTo(nextWeek);
				marketplaceContract.connect(addr1).mint(
					horseV2ContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 2024,
						payoutTier: 1,
					},
					"0x",
					[], // AvatarIDs
					{
						value: horseV2Price * 2,
					}
				);
			});

			// use deployWith4Discounts and create the previous 2 tests
			it("Should return current discounts", async () => {
				const {
					marketplaceContract,
					addr1,
					avatarContract,
					avatarContractAddress,
					avatarPrice,
					horseV2Contract,
					horseV2ContractAddress,
					horseV2Price,
				} = await loadFixture(deployWith2Discounts);

				let discounts = await marketplaceContract.getActiveDiscounts(2024);
				expect(discounts.length).to.equal(1);

				const discountPercentage = discounts[0].discount;
				const discountStartDate = discounts[0].discountStartDate;
				const discountExpiration = discounts[0].discountExpiration;
				const avatarStartId = discounts[0].avatarStartId;
				const avatarEndId = discounts[0].avatarEndId;
				const usedAvatarTokens = discounts[0].usedAvatarTokens;
				expect(discountPercentage).to.equal(10);
				expect(discountStartDate).to.equal(1706745600);
				expect(discountExpiration).to.equal(1709078400);
				expect(avatarStartId).to.equal(0);
				expect(avatarEndId).to.equal(3730);
				expect(usedAvatarTokens.length).to.equal(0);

				const feb212024 = new Date("2024-02-21T00:00:00Z");
				// const feb202024Timestamp = Math.floor(feb202024.getTime() / 1000);

				await time.increaseTo(feb212024);
				discounts = await marketplaceContract.getActiveDiscounts(2024);

				expect(discounts.length).to.equal(2);

				// Mint 2 avatars for addr1
				await marketplaceContract.connect(addr1).mint(
					avatarContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 0,
						payoutTier: 0,
					},
					"0x",
					[], // AvatarIDs
					{
						value: avatarPrice * 2,
					}
				);

				// Mint 2 horses for addr1
				await marketplaceContract.connect(addr1).mint(
					horseV2ContractAddress,
					{
						to: addr1.address,
						quantity: 2,
						seasonId: 2024,
						payoutTier: 1,
					},
					"0x",
					[], // AvatarIDs
					{
						value: horseV2Price * 2,
					}
				);
			});
		});
	});
});
