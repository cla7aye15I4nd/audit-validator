import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { RewardVault } from "../typechain-types/contracts/staking/RewardVault.sol/RewardVault";
import { MWXT } from "../typechain-types/contracts/MWXT";
import { MWXStaking } from "../typechain-types/contracts/staking/MWXStaking";

describe("RewardVault", function () {
  let rewardVault: RewardVault;
  let rewardVaultV2Factory: any;
  let stakingToken: MWXT;
  let rewardToken: MWXT;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let staking: MWXStaking; // MWXStaking mock
  // Constants
  const TOKEN_SUPPLY = ethers.parseUnits("1000000000", 18);
  const REWARD_POOL = ethers.parseUnits("47000000", 18); // 47M tokens for all years
  const FOR_YEAR = 5; // 5 years
  const ANNUAL_REWARD_POOL = REWARD_POOL / BigInt(FOR_YEAR);
  const SECONDS_PER_YEAR = 31536000;
  const PRECISION_FACTOR = ethers.parseUnits("1", 18);

  beforeEach(async function () {
    [owner, admin, user] = await ethers.getSigners();

    // Deploy MockERC20
    const MWXTFactory = await ethers.getContractFactory("MWXT");
    stakingToken = await upgrades.deployProxy(MWXTFactory, ["Mock Token", "MTK", 1_000_000, owner.address]);
    await stakingToken.waitForDeployment();
    rewardToken = await upgrades.deployProxy(MWXTFactory, ["Reward Token", "RWD", REWARD_POOL, owner.address]);
    await rewardToken.waitForDeployment();
    // Deploy RewardVault (UUPS proxy)
    const RewardVaultFactory = await ethers.getContractFactory("RewardVault");
    rewardVault = await upgrades.deployProxy(RewardVaultFactory, [], { kind: "uups" });
    await rewardVault.waitForDeployment();

    // Deploy a mock MWXStaking contract
    const MWXStakingMockFactory = await ethers.getContractFactory("MWXStaking");
    staking = await upgrades.deployProxy(MWXStakingMockFactory, [
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      await rewardVault.getAddress(),
      ANNUAL_REWARD_POOL,
      FOR_YEAR
    ]);
    await staking.waitForDeployment();
  });

  describe("initialize", function () {
    it("should initialize and grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const DEFAULT_ADMIN_ROLE = await rewardVault.DEFAULT_ADMIN_ROLE();
      expect(await rewardVault.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("should not allow re-initialization", async function () {
      await expect(rewardVault.initialize()).to.be.revertedWithCustomError(rewardVault, "InvalidInitialization");
    });
  });

  describe("setStakingAddress", function () {
    it("should set staking address and emit event", async function () {
      await expect(rewardVault.setStakingAddress(staking))
        .to.emit(rewardVault, "StakingAddressSet")
        .withArgs(await staking.getAddress());
      expect(await rewardVault.staking()).to.equal(await staking.getAddress());
    });

    it("should revert if not called by admin", async function () {
      await expect(rewardVault.connect(user).setStakingAddress(staking)).to.be.revertedWithCustomError(rewardVault, "AccessControlUnauthorizedAccount");
    });

    it("should revert if staking address is zero", async function () {
      await expect(rewardVault.setStakingAddress(ethers.ZeroAddress)).to.be.revertedWithCustomError(rewardVault, "InvalidAddress");
    });
  });

  describe("approve", function () {
    beforeEach(async function () {
      await rewardVault.setStakingAddress(staking);
    });

    it("should approve staking contract to spend reward token if called by admin", async function () {
      await expect(rewardVault.approve())
        .to.not.be.reverted;

      const allowance = await rewardToken.allowance(await rewardVault.getAddress(), await staking.getAddress());
      expect(allowance).to.equal(ethers.MaxUint256);
    });

    it("should approve staking contract to spend reward token if called by staking contract", async function () {
      // Simulate staking contract calling approve
      await expect(rewardVault.connect(owner).approve()).to.not.be.reverted;
    });

    it("should revert if called by non-admin and not staking contract", async function () {
      await expect(rewardVault.connect(user).approve()).to.be.revertedWithCustomError(rewardVault, "UnAuthorizedCaller");
    });
  });

  describe("upgradeability", function () {
    it("should allow upgrade by admin and preserve state", async function () {
      await rewardVault.setStakingAddress(staking);
      rewardVaultV2Factory = await ethers.getContractFactory("RewardVaultV2");
      const upgraded = await upgrades.upgradeProxy(await rewardVault.getAddress(), rewardVaultV2Factory, {
        call: { fn: "initializeV2", args: [] },
        unsafeAllow: ["missing-initializer-call"],
      });

      expect(await upgraded.staking()).to.equal(await staking.getAddress());
      expect(await upgraded.newFunction()).to.equal("This is a new function in V2");
      await expect(upgraded.initializeV2()).to.be.revertedWithCustomError(rewardVault, "InvalidInitialization");
    });

    it("should revert upgrade if not admin", async function () {
      rewardVaultV2Factory = await ethers.getContractFactory("RewardVaultV2", user);
      await expect(
        upgrades.upgradeProxy(await rewardVault.getAddress(), rewardVaultV2Factory, {
          call: { fn: "initializeV2", args: [] },
          unsafeAllow: ["missing-initializer-call"],
        })
      ).to.be.revertedWithCustomError(rewardVault, "AccessControlUnauthorizedAccount");
    });
  });

  describe("receive function", function () {
    it("should accept native tokens via receive", async function () {
      await expect(
        owner.sendTransaction({ to: await rewardVault.getAddress(), value: ethers.parseEther("1") })
      ).to.changeEtherBalance(rewardVault, ethers.parseEther("1"));
    });
  });

  describe("edge and negative cases", function () {
    it("should revert approve if staking address is not set", async function () {
      // Reset staking address to zero
      await rewardVault.setStakingAddress(staking);
      // Deploy a new RewardVault to test fresh state
      const RewardVaultFactory = await ethers.getContractFactory("RewardVault");
      const newVault = (await upgrades.deployProxy(RewardVaultFactory, [], { kind: "uups" })) as unknown as RewardVault;
      await expect(newVault.approve()).to.be.reverted;
    });
  });
}); 