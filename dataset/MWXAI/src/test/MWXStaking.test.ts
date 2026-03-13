import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MWXStaking } from "../typechain-types/contracts/staking/MWXStaking";
import { RewardVault } from "../typechain-types/contracts/staking/RewardVault.sol/RewardVault";
import { MWXT } from "../typechain-types/contracts/MWXT";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { MWXStakingV2 } from "../typechain-types";

describe("MWXStaking", function () {
  let staking: MWXStaking;
  let rewardVault: RewardVault;
  let stakingToken: MWXT;
  let rewardToken: MWXT;
  let owner: SignerWithAddress;
  let operator: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let user4: SignerWithAddress;
  let user5: SignerWithAddress;
  let other: SignerWithAddress;
  let accounts: SignerWithAddress[];

  // Constants
  const TOKEN_SUPPLY = ethers.parseUnits("1000000000", 18);
  const REWARD_POOL = ethers.parseUnits("47000000", 18); // 47M tokens for all years
  const FOR_YEAR = 5; // 5 years
  const ANNUAL_REWARD_POOL = REWARD_POOL / BigInt(FOR_YEAR);
  const SECONDS_PER_YEAR = 31536000;
  const PRECISION_FACTOR = ethers.parseUnits("1", 18);

  // Lock options
  const LOCK_OPTIONS = {
    1: { duration: 90 * 24 * 60 * 60, multiplier: ethers.parseUnits("1.25", 18) }, // 3 months, 1.25x
    2: { duration: 180 * 24 * 60 * 60, multiplier: ethers.parseUnits("1.5", 18) },  // 6 months, 1.5x
    3: { duration: 365 * 24 * 60 * 60, multiplier: ethers.parseUnits("2", 18) }     // 12 months, 2x
  };

  beforeEach(async function () {
    [owner, operator, user1, user2, user3, user4, user5, other, ...accounts] = await ethers.getSigners();

    // Deploy MockERC20 tokens
    const MWXTFactory = await ethers.getContractFactory("MWXT");
    stakingToken = await upgrades.deployProxy(MWXTFactory, ["Staking Token", "STK", TOKEN_SUPPLY, owner.address]);
    rewardToken = await upgrades.deployProxy(MWXTFactory, ["Reward Token", "RWD", REWARD_POOL, owner.address]);
    await stakingToken.waitForDeployment();
    await rewardToken.waitForDeployment();

    // Deploy RewardVault
    const RewardVaultFactory = await ethers.getContractFactory("RewardVault");
    rewardVault = (await upgrades.deployProxy(RewardVaultFactory, [])) as unknown as RewardVault;
    await rewardVault.waitForDeployment();

    // Deploy MWXStaking
    const MWXStakingFactory = await ethers.getContractFactory("MWXStaking");
    staking = (await upgrades.deployProxy(MWXStakingFactory, [
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      await rewardVault.getAddress(),
      REWARD_POOL,
      FOR_YEAR
    ])) as unknown as MWXStaking;
    await staking.waitForDeployment();

    // Set up roles
    const OPERATOR_ROLE = await staking.OPERATOR_ROLE();
    await staking.connect(owner).grantRole(OPERATOR_ROLE, operator.address);

    // Set staking address in reward vault
    await rewardVault.connect(owner).setStakingAddress(staking);

    // Fund users with staking tokens
    await stakingToken.transfer(user1.address, ethers.parseUnits("10000", 18));
    await stakingToken.transfer(user2.address, ethers.parseUnits("10000", 18));
    await stakingToken.transfer(user3.address, ethers.parseUnits("10000", 18));
    await stakingToken.transfer(user4.address, ethers.parseUnits("10000", 18));
    await stakingToken.transfer(user5.address, ethers.parseUnits("10000", 18));
    
  });

  describe("Initialization", function () {
    it("Should initialize with correct parameters", async function () {
      expect(await staking.stakingToken()).to.equal(await stakingToken.getAddress());
      expect(await staking.rewardToken()).to.equal(await rewardToken.getAddress());
      expect(await staking.rewardVault()).to.equal(await rewardVault.getAddress());
      expect(await staking.forYear()).to.equal(FOR_YEAR);
      expect(await staking.getAnnualRewardPool()).to.equal(ANNUAL_REWARD_POOL);
      expect(await staking.getEmissionPerSecond()).to.equal((ANNUAL_REWARD_POOL) / BigInt(SECONDS_PER_YEAR));
    });

    it("Should initialize default locked options", async function () {
      for (let lockId = 1; lockId <= 3; lockId++) {
        const option = await staking.getLockedOption(lockId);
        expect(option.duration).to.equal(BigInt(LOCK_OPTIONS[lockId as keyof typeof LOCK_OPTIONS].duration));
        expect(option.multiplier).to.equal(LOCK_OPTIONS[lockId as keyof typeof LOCK_OPTIONS].multiplier);
        expect(option.active).to.be.true;
      }
    });

    it("Should revert initialization with zero staking token", async function () {
      const MWXStakingFactory = await ethers.getContractFactory("MWXStaking");
      await expect(
        upgrades.deployProxy(MWXStakingFactory, [
          ethers.ZeroAddress,
          await rewardToken.getAddress(),
          await rewardVault.getAddress(),
          ANNUAL_REWARD_POOL,
          FOR_YEAR
        ])
      ).to.be.revertedWithCustomError(staking, "InvalidTokenAddress");
    });

    it("Should revert initialization with zero reward token", async function () {
      const MWXStakingFactory = await ethers.getContractFactory("MWXStaking");
      await expect(
        upgrades.deployProxy(MWXStakingFactory, [
          await stakingToken.getAddress(),
          ethers.ZeroAddress,
          await rewardVault.getAddress(),
          ANNUAL_REWARD_POOL,
          FOR_YEAR
        ])
      ).to.be.revertedWithCustomError(staking, "InvalidTokenAddress");
    });

    it("Should revert initialization with zero reward pool", async function () {
      const MWXStakingFactory = await ethers.getContractFactory("MWXStaking");
      await expect(
        upgrades.deployProxy(MWXStakingFactory, [
          await stakingToken.getAddress(),
          await rewardToken.getAddress(),
          await rewardVault.getAddress(),
          0,
          FOR_YEAR
        ])
      ).to.be.revertedWithCustomError(staking, "InvalidRewardPool");
    });

    it("Should revert initialization with zero forYear", async function () {
      const MWXStakingFactory = await ethers.getContractFactory("MWXStaking");
      await expect(
        upgrades.deployProxy(MWXStakingFactory, [
          await stakingToken.getAddress(),
          await rewardToken.getAddress(),
          await rewardVault.getAddress(),
          REWARD_POOL,
          0
        ])
      ).to.be.revertedWithCustomError(staking, "InvalidForYear");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        staking.connect(owner).initialize(
          await stakingToken.getAddress(),
          await rewardToken.getAddress(),
          await rewardVault.getAddress(),
          REWARD_POOL,
          FOR_YEAR
        )
      ).to.be.revertedWithCustomError(staking, "InvalidInitialization");
    });

    it("should revert when claim is called when no stakes", async function () {
      await expect(
        staking.connect(user1).claim(1)
      ).to.be.revertedWithCustomError(staking, "StakeNotExists");
    });

    it("should revert when claimAll is called when no stakes", async function () {  
        await expect(
            staking.connect(user1).claimAll()
        ).to.be.revertedWithCustomError(staking, "NoStakes");
    });
  });

  describe("Contract Upgradeability", function () {
    it("Should support UUPS upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXStakingV2Factory =
        await ethers.getContractFactory("MWXStakingV2");
      const upgraded = await upgrades.upgradeProxy(
        await staking.getAddress(),
        MWXStakingV2Factory,
        {
          call: {
            fn: "initializeV2",
            args: [],
          },
          unsafeAllow: ["missing-initializer-call"],
        }
      );

      const upgradedMWXStaking = upgraded as MWXStakingV2;

      // Verify state is preserved
      expect(await upgradedMWXStaking.hasRole(await upgradedMWXStaking.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
      expect(await upgradedMWXStaking.newFunction()).to.equal(
        "This is a new function in V2"
      );

      await expect(
        upgradedMWXStaking.initializeV2()
      ).to.be.revertedWithCustomError(staking, "InvalidInitialization");
    });

    it("Should only allow owner to authorize upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXStakingV2Factory = await ethers.getContractFactory(
        "MWXStakingV2",
        user1
      );
      await expect(
        upgrades.upgradeProxy(
          await staking.getAddress(),
          MWXStakingV2Factory,
          {
            call: {
              fn: "initializeV2",
              args: [],
            },
            unsafeAllow: ["missing-initializer-call"],
          }
        )
      ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Access Control", function () {
    it("Should grant DEFAULT_ADMIN_ROLE to deployer", async function () {
      const DEFAULT_ADMIN_ROLE = await staking.DEFAULT_ADMIN_ROLE();
      expect(await staking.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should grant OPERATOR_ROLE to deployer", async function () {
      const OPERATOR_ROLE = await staking.OPERATOR_ROLE();
      expect(await staking.hasRole(OPERATOR_ROLE, owner.address)).to.be.true;
    });

    it("Should allow operator to pause/unpause", async function () {
      await staking.connect(operator).pause();
      expect(await staking.paused()).to.be.true;

      await staking.connect(operator).unpause();
      expect(await staking.paused()).to.be.false;
    });

    it("Should not allow non-operator to pause", async function () {
      await expect(
        staking.connect(user1).pause()
      ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });

    it("Should not allow non-operator to unpause", async function () {
      await expect(
        staking.connect(user1).unpause()
      ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Flexible Staking", function () {
    before(async function () {
      await rewardVault.connect(owner).approve();
      // Fund reward vault
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);
    });

    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
    });

    it("Should stake flexible tokens successfully", async function () {
      const stake = await staking.connect(user1).stake(stakeAmount, 0);
      await expect(stake).to.emit(staking, "Staked")
        .withArgs(user1.address, 1, 0, stakeAmount, stakeAmount, 0);

      const stakeId = await staking.userNonce(user1.address);
      const stakeInfo = await staking.getStakeById(user1.address, stakeId);
      
      expect(stakeInfo.owner).to.equal(user1.address);
      expect(stakeInfo.stakeType).to.equal(0); // FLEXIBLE
      expect(stakeInfo.amount).to.equal(stakeAmount);
      expect(stakeInfo.effectiveAmount).to.equal(stakeAmount);
      expect(stakeInfo.multiplier).to.equal(PRECISION_FACTOR);
      expect(stakeInfo.unlockTime).to.equal(0);
      expect(stakeInfo.active).to.be.true;
      expect(stakeInfo.lockId).to.equal(0);
    });

    it("Should update totals correctly for flexible staking", async function () {
      await staking.connect(user1).stake(stakeAmount, 0);

      expect(await staking.totalFlexibleStaked()).to.equal(stakeAmount);
      expect(await staking.totalLockedStaked()).to.equal(0);
      expect(await staking.totalEffectiveStake()).to.equal(stakeAmount);
      expect(await staking.uniqueStakers()).to.equal(1);
      expect(await staking.userTotalStaked(user1.address)).to.equal(stakeAmount);
    });

    it("Should increment unique stakers only once per user", async function () {
      await staking.connect(user1).stake(stakeAmount, 0);
      expect(await staking.uniqueStakers()).to.equal(1);

      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
      expect(await staking.uniqueStakers()).to.equal(1); // Should not increment
    });

    it("Should revert flexible staking with zero amount", async function () {
      await expect(
        staking.connect(user1).stake(0, 0)
      ).to.be.revertedWithCustomError(staking, "InvalidStakeAmount");
    });

    it("Should revert flexible staking when paused", async function () {
      await staking.connect(operator).pause();
      await expect(
        staking.connect(user1).stake(stakeAmount, 0)
      ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    it("Should revert flexible staking with insufficient allowance", async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), 0);
      await expect(
        staking.connect(user1).stake(stakeAmount, 0)
      ).to.be.revertedWithCustomError(stakingToken, "ERC20InsufficientAllowance")
        .withArgs(await staking.getAddress(), 0, stakeAmount);
    });

    it("Should revert flexible staking with insufficient balance", async function () {
      const largeAmount = ethers.parseUnits("50000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), largeAmount);
      await expect(
        staking.connect(user1).stake(largeAmount, 0)
      ).to.be.revertedWithCustomError(stakingToken, "ERC20InsufficientBalance")
        .withArgs(user1.address, await stakingToken.balanceOf(user1.address), largeAmount);
    });
  });

  describe("Locked Staking", function () {
    before(async function () {
      await rewardVault.connect(owner).approve();
      // Fund reward vault
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);
    });

    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
    });

    it("Should stake locked tokens successfully for lock option 1", async function () {
      const lockId = 1;
      const stake = await staking.connect(user1).stake(stakeAmount, lockId);
      await expect(stake).to.emit(staking, "Staked")
        .withArgs(user1.address, 1, 1, stakeAmount, stakeAmount * BigInt(LOCK_OPTIONS[lockId].multiplier) / PRECISION_FACTOR, LOCK_OPTIONS[lockId].duration);

      const stakeInfo = await staking.getStakeById(user1.address, 1);
      const lockOption = await staking.getLockedOption(lockId);
      
      expect(stakeInfo.stakeType).to.equal(1); // LOCKED
      expect(stakeInfo.amount).to.equal(stakeAmount);
      expect(stakeInfo.effectiveAmount).to.equal(stakeAmount * lockOption.multiplier / PRECISION_FACTOR);
      expect(stakeInfo.multiplier).to.equal(lockOption.multiplier);
      expect(stakeInfo.unlockTime).to.be.gt(await time.latest());
      expect(stakeInfo.active).to.be.true;
      expect(stakeInfo.lockId).to.equal(lockId);
    });

    it("Should update totals correctly for locked staking", async function () {
      const lockId = 1;
      await staking.connect(user1).stake(stakeAmount, lockId);

      const lockOption = await staking.getLockedOption(lockId);
      const effectiveAmount = stakeAmount * lockOption.multiplier / PRECISION_FACTOR;

      expect(await staking.totalFlexibleStaked()).to.equal(0);
      expect(await staking.totalLockedStaked()).to.equal(stakeAmount);
      expect(await staking.totalEffectiveStake()).to.equal(effectiveAmount);
      expect(await staking.totalStakedPerLock(lockId)).to.equal(stakeAmount);
    });

    it("Should revert locked staking with inactive lock option", async function () {
      await staking.connect(operator).setLockedOption(1, LOCK_OPTIONS[1].duration, LOCK_OPTIONS[1].multiplier, false);
      
      await expect(
        staking.connect(user1).stake(stakeAmount, 1)
      ).to.be.revertedWithCustomError(staking, "LockOptionNotActive");
    });

    it("Should revert locked staking with invalid lock ID", async function () {
      await expect(
        staking.connect(user1).stake(stakeAmount, 99)
      ).to.be.revertedWithCustomError(staking, "LockOptionNotActive");
    });
  });

  describe("Unstaking", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await rewardVault.connect(owner).approve();
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);

      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
    });

    it("Should unstake flexible tokens successfully", async function () {
      const balanceBefore = await stakingToken.balanceOf(user1.address);
      await staking.connect(user1).unstake(1);
      const balanceAfter = await stakingToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.gte(stakeAmount);

      const stakeInfo = await staking.getStakeById(user1.address, 1);
      expect(stakeInfo.active).to.be.false;
    });

    it("Should unstake correctly stake id from multiple stakes", async function () {
        await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount * BigInt(5));

        await staking.connect(user1).stake(stakeAmount, 0);
        await staking.connect(user1).stake(stakeAmount, 0);
        await staking.connect(user1).stake(stakeAmount, 1);
        await staking.connect(user1).stake(stakeAmount, 2);
        await staking.connect(user1).stake(stakeAmount, 3);

        const balanceBefore = await stakingToken.balanceOf(user1.address);
        await staking.connect(user1).unstake(3);
        const balanceAfter = await stakingToken.balanceOf(user1.address);

        expect(balanceAfter - balanceBefore).to.gte(stakeAmount);

        const stakeInfo = await staking.getStakeById(user1.address, 3);
        expect(stakeInfo.active).to.be.false;
    });

    it("Should update totals correctly after unstaking", async function () {
      await staking.connect(user1).unstake(1);

      expect(await staking.totalFlexibleStaked()).to.equal(0);
      expect(await staking.totalEffectiveStake()).to.equal(0);
      expect(await staking.userTotalStaked(user1.address)).to.equal(0);
    });

    it("Should revert unstaking non-existent stake", async function () {
      await expect(
        staking.connect(user1).unstake(99)
      ).to.be.revertedWithCustomError(staking, "StakeNotExists");
    });

    it("Should revert unstaking other user's stake", async function () {
      await expect(
        staking.connect(user2).unstake(1)
      ).to.be.revertedWithCustomError(staking, "StakeNotExists");
    });

    it("Should revert unstaking when paused", async function () {
      await staking.connect(operator).pause();
      await expect(
        staking.connect(user1).unstake(1)
      ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    it("Should auto-claim rewards when unstaking flexible stake", async function () {
      // accrue rewards
      await time.increase(30 * 24 * 60 * 60);
      const rewardBalanceBefore = await rewardToken.balanceOf(user1.address);
      const totalRewardsClaimedBefore = await staking.totalRewardsClaimed();

      await staking.connect(user1).unstake(1);

      const rewardBalanceAfter = await rewardToken.balanceOf(user1.address);
      const totalRewardsClaimedAfter = await staking.totalRewardsClaimed();

      expect(rewardBalanceAfter).to.be.gt(rewardBalanceBefore);
      expect(totalRewardsClaimedAfter).to.be.gt(totalRewardsClaimedBefore);
    });
  });

  describe("Locked Staking Unstaking", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);
    const lockId = 1;

    beforeEach(async function () {
      await rewardVault.connect(owner).approve();
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);

      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, lockId);
    });

    it("Should revert unstaking locked tokens before unlock time", async function () {
      await expect(
        staking.connect(user1).unstake(1)
      ).to.be.revertedWithCustomError(staking, "StakeStillLocked");
    });

    it("Should allow unstaking locked tokens after unlock time", async function () {
      const lockOption = await staking.getLockedOption(lockId);
      await time.increase(lockOption.duration + 1n);

      const balanceBefore = await stakingToken.balanceOf(user1.address);
      await staking.connect(user1).unstake(1);
      const balanceAfter = await stakingToken.balanceOf(user1.address);
      expect(balanceAfter - balanceBefore).to.equal(stakeAmount);
    });

    it("Should auto-claim rewards when unstaking locked stake after unlock time", async function () {
      const lockOption = await staking.getLockedOption(lockId);
      // accrue rewards beyond unlock
      await time.increase(lockOption.duration + 1n);
      const rewardBalanceBefore = await rewardToken.balanceOf(user1.address);
      const totalRewardsClaimedBefore = await staking.totalRewardsClaimed();

      await staking.connect(user1).unstake(1);

      const rewardBalanceAfter = await rewardToken.balanceOf(user1.address);
      const totalRewardsClaimedAfter = await staking.totalRewardsClaimed();

      expect(rewardBalanceAfter).to.be.gt(rewardBalanceBefore);
      expect(totalRewardsClaimedAfter).to.be.gt(totalRewardsClaimedBefore);
    });

    it("Should allow emergency unstaking of locked tokens", async function () {
      const balanceBefore = await stakingToken.balanceOf(user1.address);
      await staking.connect(user1).emergencyUnstake(1);
      const balanceAfter = await stakingToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.equal(stakeAmount);

      const stakeInfo = await staking.getStakeById(user1.address, 1);
      expect(stakeInfo.active).to.be.false;
    });

    it("Should forfeit rewards on emergency unstake", async function () {
      // Advance time to accumulate rewards
      await time.increase(30 * 24 * 60 * 60); // 30 days

      const pendingRewards = await staking.getPendingRewards(user1.address, 1);
      expect(pendingRewards).to.be.gt(0);

      await expect(staking.connect(user1).emergencyUnstake(1))
        .to.emit(staking, "EmergencyUnstaked")

      // Rewards should be forfeited
      const finalRewards = await staking.getPendingRewards(user1.address, 1);
      expect(finalRewards).to.equal(0);
    });

    it("Should revert emergency unstake if staking is paused", async function () {
        await staking.connect(operator).pause();

        // Advance time to accumulate rewards
        await time.increase(30 * 24 * 60 * 60); // 30 days
  
        const pendingRewards = await staking.getPendingRewards(user1.address, 1);
        expect(pendingRewards).to.be.gt(0);
  
        await expect(staking.connect(user1).emergencyUnstake(1))
          .to.be.revertedWithCustomError(staking, "EnforcedPause");
    });
  });

  describe("Reward Calculation", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await rewardVault.connect(owner).approve();
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);
      
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
    });

    it("Should calculate rewards correctly", async function () {
      const initialRewards = await staking.getPendingRewards(user1.address, 1);
      expect(initialRewards).to.equal(0);

      // Advance time
      await time.increase(30 * 24 * 60 * 60); // 30 days

      const rewardsAfter = await staking.getPendingRewards(user1.address, 1);
      expect(rewardsAfter).to.be.gt(0);
    });

    it("Should calculate APR correctly", async function () {
      const apr = await staking.getCurrentAPR();
      expect(apr).to.be.gt(0);
    });

    it("Should return zero APR when no stakes", async function () {
      await staking.connect(user1).unstake(1);
      const apr = await staking.getCurrentAPR();
      expect(apr).to.equal(0);
    });

    it("Should calculate reward per token correctly", async function () {
      const rewardPerToken = await staking.rewardPerToken();
      expect(rewardPerToken).to.be.gte(0);
    });

    it("Should return zero reward per token when no stakes", async function () {
      await staking.connect(user1).unstake(1);
      const rewardPerToken = await staking.rewardPerToken();
      expect(rewardPerToken).to.equal(0);
    });
  });

  describe("Reward Claiming", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await rewardVault.connect(owner).approve();
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);

      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
      await time.increase(30 * 24 * 60 * 60); // 30 days to accumulate rewards
    });

    it("Should claim rewards for specific stake", async function () {
      const pendingRewards = await staking.getPendingRewards(user1.address, 1);
      expect(pendingRewards).to.be.gt(0);

      const balanceBefore = await rewardToken.balanceOf(user1.address);
      await staking.connect(user1).claim(1);
      const balanceAfter = await rewardToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.gt(pendingRewards);
    });

    it("Should claim all rewards", async function () {
      // Create second stake
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);

      const totalPendingRewards = await staking.getUserTotalPendingRewards(user1.address);
      expect(totalPendingRewards).to.be.gt(0);

      const balanceBefore = await rewardToken.balanceOf(user1.address);
      await staking.connect(user1).claimAll();
      const balanceAfter = await rewardToken.balanceOf(user1.address);

      expect(balanceAfter - balanceBefore).to.gt(totalPendingRewards);
    });

    // it("Should revert claiming with no pending rewards", async function () {
    //   const timeLatest = await time.latest();
    //   await staking.connect(user1).claim(1);
    //   await time.setNextBlockTimestamp(timeLatest);
    //   await expect(
    //     staking.connect(user1).claim(1)
    //   ).to.be.revertedWithCustomError(staking, "NoPendingRewards");
    // });

    it("Should revert claimAll with no stakes", async function () {
      await staking.connect(user1).unstake(1);
      await expect(
        staking.connect(user1).claimAll()
      ).to.be.revertedWithCustomError(staking, "NoStakes");
    });

    it("Should revert claimAll when staking is paused", async function () {
        await staking.connect(operator).pause();
        await expect(
          staking.connect(user1).claimAll()
        ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    // it("Should revert claimAll with no pending rewards", async function () {
    //   await staking.connect(user1).claimAll();
    //   await expect(
    //     staking.connect(user1).claimAll()
    //   ).to.be.revertedWithCustomError(staking, "NoPendingRewards");
    // });
  });

  describe("Admin Functions", function () {
    it("Should set reward vault correctly", async function () {
      const newVault = await ethers.deployContract("RewardVault");
      await staking.connect(owner).setRewardVault(await newVault.getAddress());
      expect(await staking.rewardVault()).to.equal(await newVault.getAddress());
    });

    it("Should revert setting reward vault with zero address", async function () {
      await expect(
        staking.connect(owner).setRewardVault(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(staking, "InvalidAddress");
    });

    it("Should revert setting reward vault when caller is not an admin", async function () {
      await expect(
        staking.connect(user1).setRewardVault(await staking.rewardVault())
      ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });

    it("Should set reward pool correctly", async function () {
      const newRewardPool = ethers.parseUnits("200000", 18);
      const newForYear = 5;
      
      await staking.connect(operator).setRewardPool(newRewardPool, newForYear);
      
      expect(await staking.forYear()).to.equal(newForYear);
      expect(await staking.getAnnualRewardPool()).to.equal(newRewardPool / BigInt(newForYear));
    });

    it("Should revert setting reward pool if caller is not admin", async function () {
        await expect(
          staking.connect(user1).setRewardPool(REWARD_POOL, FOR_YEAR)
        ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });

    it("Should revert setting reward pool with zero amount", async function () {
      await expect(
        staking.connect(operator).setRewardPool(0, FOR_YEAR)
      ).to.be.revertedWithCustomError(staking, "InvalidRewardPool");
    });

    it("Should revert setting reward pool with zero forYear", async function () {
      await expect(
        staking.connect(operator).setRewardPool(ANNUAL_REWARD_POOL, 0)
      ).to.be.revertedWithCustomError(staking, "InvalidForYear");
    });

    it("Should set locked option correctly", async function () {
      const newDuration = 120 * 24 * 60 * 60; // 120 days
      const newMultiplier = ethers.parseUnits("1.75", 18);
      
      await staking.connect(operator).setLockedOption(4, newDuration, newMultiplier, true);
      
      const option = await staking.getLockedOption(4);
      expect(option.duration).to.equal(BigInt(newDuration));
      expect(option.multiplier).to.equal(newMultiplier);
      expect(option.active).to.be.true;
    });

    it("Should change active to false for locked option correctly", async function () {
        await staking.connect(operator).setLockedOption(2, LOCK_OPTIONS[2].duration, LOCK_OPTIONS[2].multiplier, false);

        const option = await staking.getLockedOption(2);
        expect(option.active).to.be.false;
    });

    it("Should revert setting locked option with zero duration", async function () {
      await expect(
        staking.connect(operator).setLockedOption(4, 0, ethers.parseUnits("1.5", 18), true)
      ).to.be.revertedWithCustomError(staking, "InvalidDuration");
    });

    it("Should revert setting locked option with invalid multiplier", async function () {
      await expect(
        staking.connect(operator).setLockedOption(4, 90 * 24 * 60 * 60, ethers.parseUnits("0.5", 18), true)
      ).to.be.revertedWithCustomError(staking, "InvalidMultiplier");
    });

    it("Should revert setting locked option if caller is not operator", async function () {
        await expect(
          staking.connect(user1).setLockedOption(4, 90 * 24 * 60 * 60, ethers.parseUnits("0.5", 18), true)
        ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });

    it("Should withdraw foreign tokens correctly", async function () {
      const foreignToken = await ethers.deployContract("MockERC20", ["Foreign", "FGN", 1000000]);
      await foreignToken.transfer(await staking.getAddress(), ethers.parseUnits("1000", 6));

      const balanceBefore = await foreignToken.balanceOf(other.address);
      await staking.connect(owner).withdrawForeignToken(
        await foreignToken.getAddress(),
        other.address,
        ethers.parseUnits("500", 6)
      );
      const balanceAfter = await foreignToken.balanceOf(other.address);

      expect(balanceAfter - balanceBefore).to.equal(ethers.parseUnits("500", 6));
    });

    it("Should withdraw native tokens correctly", async function () {
      await owner.sendTransaction({
        to: await staking.getAddress(),
        value: ethers.parseUnits("1", 18)
      });

      const balanceBefore = await ethers.provider.getBalance(other.address);
      await staking.connect(owner).withdrawForeignToken(
        ethers.ZeroAddress,
        other.address,
        ethers.parseUnits("0.5", 18)
      );
      const balanceAfter = await ethers.provider.getBalance(other.address);

      expect(balanceAfter - balanceBefore).to.equal(ethers.parseUnits("0.5", 18));
    });

    it("Should revert withdrawing foreign tokens insufficient balance", async function () {
      const foreignToken = await ethers.deployContract("MockERC20", ["Foreign", "FGN", 1000000]);
      await foreignToken.connect(owner).transfer(await staking.getAddress(), ethers.parseUnits("1000", 6));

      await expect(staking.connect(owner).withdrawForeignToken(
        await foreignToken.getAddress(),
        other.address,
        ethers.parseUnits("1001", 6)
      )).to.be.revertedWithCustomError(staking, "ERC20InsufficientBalance");
    });

    it("Should revert withdrawing native tokens insufficient balance", async function () {
      await expect(staking.connect(owner).withdrawForeignToken(
        ethers.ZeroAddress,
        other.address,
        ethers.parseUnits("1", 18)
      )).to.be.revertedWithCustomError(staking, "InsufficientBalance");
    });

    it("Should revert withdrawing staking token", async function () {
      await expect(
        staking.connect(owner).withdrawForeignToken(
          await stakingToken.getAddress(),
          other.address,
          ethers.parseUnits("100", 18)
        )
      ).to.be.revertedWithCustomError(staking, "InvalidTokenAddress");
    });

    it("Should revert withdrawing reward token", async function () {
      
      await expect(
        staking.connect(owner).withdrawForeignToken(
          await rewardToken.getAddress(),
          other.address,
          ethers.parseUnits("100", 18)
        )
      ).to.be.revertedWithCustomError(staking, "InvalidTokenAddress");
    });

    it("Should revert withdrawing with zero recipient", async function () {
      const foreignToken = await ethers.deployContract("MockERC20", ["Foreign", "FGN", 1000000]);
      await expect(
        staking.connect(owner).withdrawForeignToken(
          await foreignToken.getAddress(),
          ethers.ZeroAddress,
          ethers.parseUnits("100", 6)
        )
      ).to.be.revertedWithCustomError(staking, "InvalidAddress");
    });

    it("Should revert withdrawing with zero amount", async function () {
      const foreignToken = await ethers.deployContract("MockERC20", ["Foreign", "FGN", 1000000]);
      await expect(
        staking.connect(owner).withdrawForeignToken(
          await foreignToken.getAddress(),
          other.address,
          0
        )
      ).to.be.revertedWithCustomError(staking, "InvalidAmount");
    });

    it("Should revert withdrawing if caller is not an admin", async function () {
      const foreignToken = await ethers.deployContract("MockERC20", ["Foreign", "FGN", 1000000]);
      await expect(
        staking.connect(user1).withdrawForeignToken(
          await foreignToken.getAddress(),
          other.address,
          ethers.parseUnits("100", 6)
        )
      ).to.be.revertedWithCustomError(staking, "AccessControlUnauthorizedAccount");
    });
  });

  describe("View Functions", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
    });

    it("Should return correct user stake count", async function () {
      expect(await staking.getUserStakeCount(user1.address)).to.equal(1);
    });

    it("Should return correct user stakes with pagination", async function () {
      const [stakes, total] = await staking.getUserStakes(user1.address, 0, 10);
      expect(total).to.equal(1);
      expect(stakes.length).to.equal(1);
      expect(stakes[0].owner).to.equal(user1.address);
    });

    it("Should return empty user stakes if offset is greater than total", async function () {
      const [stakes, total] = await staking.getUserStakes(user1.address, 2, 10);
      expect(total).to.equal(1);
      expect(stakes.length).to.equal(0);
    });

    it("Should return limit user stakes if limit is greater than total", async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
      const [stakes, total] = await staking.getUserStakes(user1.address, 0, 1);
      expect(total).to.equal(2);
      expect(stakes.length).to.equal(1);
    });

    it("Should return correct total user staked", async function () {
      const [totalStaked, totalEffectiveStaked] = await staking.getTotalUserStaked(user1.address);
      expect(totalStaked).to.equal(stakeAmount);
      expect(totalEffectiveStaked).to.equal(stakeAmount);
    });

    it("Should return active lock IDs", async function () {
      const activeLockIds = await staking.getActiveLockIds();
      expect(activeLockIds.length).to.equal(3);
      expect(activeLockIds[0]).to.equal(1);
      expect(activeLockIds[1]).to.equal(2);
      expect(activeLockIds[2]).to.equal(3);
    });

    it("Should return total reward pool for all years", async function () {
      const totalPool = await staking.getTotalRewardPoolAllYear();
      expect(Math.ceil(Number(ethers.formatUnits(totalPool, 18)))).to.equal(Math.ceil(Number(ethers.formatUnits(REWARD_POOL, 18))));
    });
  });

  describe("Edge Cases", function () {
    before(async function () {
      await rewardVault.connect(owner).approve();
      // Fund reward vault
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);
    });

    it("Should handle multiple stakes from same user", async function () {
      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount * BigInt(4));

      await staking.connect(user1).stake(stakeAmount, 0);
      await staking.connect(user1).stake(stakeAmount, 1);
      await staking.connect(user1).stake(stakeAmount, 2);
      await staking.connect(user1).stake(stakeAmount, 3);

      const totalStakedAmount = stakeAmount 
        + (stakeAmount * LOCK_OPTIONS[1].multiplier / PRECISION_FACTOR) 
        + (stakeAmount * LOCK_OPTIONS[2].multiplier / PRECISION_FACTOR) 
        + (stakeAmount * LOCK_OPTIONS[3].multiplier / PRECISION_FACTOR);

      expect(await staking.getUserStakeCount(user1.address)).to.equal(4);
      expect(await staking.userTotalStaked(user1.address)).to.equal(stakeAmount * BigInt(4));
      expect(await staking.userTotalEffectiveStaked(user1.address)).to.equal(totalStakedAmount);
    });

    it("Should handle multiple users staking", async function () {
      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await stakingToken.connect(user2).approve(await staking.getAddress(), stakeAmount);

      await staking.connect(user1).stake(stakeAmount, 0);
      await staking.connect(user2).stake(stakeAmount, 0);

      expect(await staking.uniqueStakers()).to.equal(2);
      expect(await staking.totalFlexibleStaked()).to.equal(stakeAmount * BigInt(2));
      expect(await staking.totalEffectiveStake()).to.equal(stakeAmount * BigInt(2));
    });

    it("Should handle deactivating and reactivating lock options", async function () {
      // Deactivate lock option 1
      await staking.connect(operator).setLockedOption(1, LOCK_OPTIONS[1].duration, LOCK_OPTIONS[1].multiplier, false);
      
      let activeLockIds = await staking.getActiveLockIds();
      expect(activeLockIds.length).to.equal(2);

      // Reactivate lock option 1
      await staking.connect(operator).setLockedOption(1, LOCK_OPTIONS[1].duration, LOCK_OPTIONS[1].multiplier, true);
      
      activeLockIds = await staking.getActiveLockIds();
      expect(activeLockIds.length).to.equal(3);
    });

    it("Should handle reward calculation with time advancement", async function () {
      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);

      const rewards1 = await staking.getPendingRewards(user1.address, 1);
      await time.increase(30 * 24 * 60 * 60); // 30 days
      const rewards2 = await staking.getPendingRewards(user1.address, 1);
      await time.increase(30 * 24 * 60 * 60); // 60 days total
      const rewards3 = await staking.getPendingRewards(user1.address, 1);

      expect(rewards2).to.be.gt(rewards1);
      expect(rewards3).to.be.gt(rewards2);
    });

    it("Should handle locked staking with different multipliers", async function () {
      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount * BigInt(3));

      await staking.connect(user1).stake(stakeAmount, 1); // 1.25x multiplier
      await staking.connect(user1).stake(stakeAmount, 2); // 1.5x multiplier
      await staking.connect(user1).stake(stakeAmount, 3); // 2x multiplier

      const [totalStaked, totalEffectiveStaked] = await staking.getTotalUserStaked(user1.address);
      expect(totalStaked).to.equal(stakeAmount * BigInt(3));
      expect(totalEffectiveStaked).to.be.gt(totalStaked); // Due to multipliers
    });
  });

  describe("Pause/Unpause Functionality", function () {
    const stakeAmount = ethers.parseUnits("1000", 18);

    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
    });

    it("Should prevent staking when paused", async function () {
      await staking.connect(operator).pause();
      await expect(
        staking.connect(user1).stake(stakeAmount, 0)
      ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    it("Should prevent unstaking when paused", async function () {
      await staking.connect(user1).stake(stakeAmount, 0);
      await staking.connect(operator).pause();
      await expect(
        staking.connect(user1).unstake(1)
      ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    it("Should prevent claiming when paused", async function () {
      await staking.connect(user1).stake(stakeAmount, 0);
      await time.increase(30 * 24 * 60 * 60); // 30 days
      await staking.connect(operator).pause();
      await expect(
        staking.connect(user1).claim(1)
      ).to.be.revertedWithCustomError(staking, "EnforcedPause");
    });

    it("Should allow operations after unpause", async function () {
      await staking.connect(operator).pause();
      await staking.connect(operator).unpause();
      
      await staking.connect(user1).stake(stakeAmount, 0);
      expect(await staking.getUserStakeCount(user1.address)).to.equal(1);
    });
  });

  describe("Reward Vault Integration", function () {
    it("Should claim rewards from reward vault", async function () {
      await rewardVault.connect(owner).approve();
      await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);

      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
      
      await time.increase(30 * 24 * 60 * 60); // 30 days
      
      const balanceBefore = await rewardToken.balanceOf(user1.address);
      await staking.connect(user1).claim(1);
      const balanceAfter = await rewardToken.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.be.gt(0);
    });

    it("Should revert claiming when reward vault has insufficient balance", async function () {
      const stakeAmount = ethers.parseUnits("1000", 18);
      await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(user1).stake(stakeAmount, 0);
      
      await time.increase(30 * 24 * 60 * 60); // 30 days
      
      await expect(
        staking.connect(user1).claim(1)
      ).to.be.revertedWithCustomError(staking, "BalanceNotEnough");
    });

    it("Should revert claiming when reward vault has insufficient allowance", async function () {
        await rewardToken.transfer(await rewardVault.getAddress(), REWARD_POOL);
        const stakeAmount = ethers.parseUnits("1000", 18);
        await stakingToken.connect(user1).approve(await staking.getAddress(), stakeAmount);
        await staking.connect(user1).stake(stakeAmount, 0);
        
        await time.increase(30 * 24 * 60 * 60); // 30 days
        
        await expect(
          staking.connect(user1).claim(1)
        ).to.be.revertedWithCustomError(staking, "InsufficientAllowance");
    });
  });
}); 