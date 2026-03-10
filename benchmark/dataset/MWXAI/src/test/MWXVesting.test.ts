import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MWXVesting } from "../typechain-types/contracts/MWXVesting";
import { MockERC20 } from "../typechain-types/contracts/mocks/MockERC20";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { MWXVestingV2 } from "../typechain-types";

describe("MWXVesting", function () {
  let vesting: MWXVesting;
  let token: MockERC20;
  let owner: SignerWithAddress;
  let scheduleManager: SignerWithAddress;
  let releaser: SignerWithAddress;
  let admin: SignerWithAddress;
  let beneficiary1: SignerWithAddress;
  let beneficiary2: SignerWithAddress;
  let beneficiary3: SignerWithAddress;
  let other: SignerWithAddress;
  let accounts: SignerWithAddress[];

  const TOKEN_SUPPLY = ethers.parseUnits("1000000", 6);
  const VESTING_PARAMS = {
    startTimestamp: 0, // will be set in beforeEach
    cliffDuration: 60 * 60 * 24 * 30, // 30 days
    vestingDuration: 60 * 60 * 24 * 365, // 1 year
    releaseIntervalDays: 30, // 30 days
  };
  const MAX_BATCH_CREATE = 5;
  const MAX_BATCH_RELEASE = 5;

  beforeEach(async function () {
    [owner, scheduleManager, releaser, admin, beneficiary1, beneficiary2, beneficiary3, other, ...accounts] = await ethers.getSigners();

    // Deploy MockERC20
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    token = await MockERC20Factory.deploy("Mock Token", "MOCK", TOKEN_SUPPLY);
    await token.waitForDeployment();

    // Set vesting start time to now + 1 hour
    const now = await time.latest();
    VESTING_PARAMS.startTimestamp = now + 3600;

    // Deploy MWXVesting as upgradeable proxy
    const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
    vesting = (await upgrades.deployProxy(MWXVestingFactory, [
      owner.address,
      scheduleManager.address,
      MAX_BATCH_CREATE,
      MAX_BATCH_RELEASE,
      VESTING_PARAMS
    ])) as unknown as MWXVesting;
    await vesting.waitForDeployment();

    // Grant releaser role
    const RELEASER_ROLE = await vesting.RELEASER_ROLE();
    await vesting.connect(owner).grantRole(RELEASER_ROLE, releaser.address);
    // Grant admin role
    const DEFAULT_ADMIN_ROLE = await vesting.DEFAULT_ADMIN_ROLE();
    await vesting.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, admin.address);
    // Set vesting token
    await vesting.connect(admin).setVestingToken(await token.getAddress());
    // Fund vesting contract with tokens
    await token.transfer(await vesting.getAddress(), ethers.parseUnits("500000", 6));
  });

  describe("Initialization", function () {
    it("should initialize with correct parameters", async function () {
      expect(await vesting.vestingToken()).to.equal(await token.getAddress());
      expect(await vesting.owner()).to.equal(owner.address);
      expect(await vesting.maxBatchForCreateVestingSchedule()).to.equal(MAX_BATCH_CREATE);
      expect(await vesting.maxBatchForRelease()).to.equal(MAX_BATCH_RELEASE);
      const params = await vesting.getDefaultVestingParams();
      expect(params.startTimestamp).to.equal(BigInt(VESTING_PARAMS.startTimestamp));
      expect(params.cliffDuration).to.equal(BigInt(VESTING_PARAMS.cliffDuration));
      expect(params.vestingDuration).to.equal(BigInt(VESTING_PARAMS.vestingDuration));
      expect(params.releaseIntervalDays).to.equal(BigInt(VESTING_PARAMS.releaseIntervalDays));
    });

    it("should revert if initialized with zero addresses", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      await expect(
        upgrades.deployProxy(MWXVestingFactory, [
          ethers.ZeroAddress,
          scheduleManager.address,
          MAX_BATCH_CREATE,
          MAX_BATCH_RELEASE,
          VESTING_PARAMS
        ])
      ).to.be.revertedWithCustomError(vesting, "InvalidAddress");
      await expect(
        upgrades.deployProxy(MWXVestingFactory, [
          owner.address,
          ethers.ZeroAddress,
          MAX_BATCH_CREATE,
          MAX_BATCH_RELEASE,
          VESTING_PARAMS
        ])
      ).to.be.revertedWithCustomError(vesting, "InvalidAddress");
    });

    it("should revert if vesting params are invalid", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      const badParams = { ...VESTING_PARAMS, vestingDuration: 0 };
      await expect(
        upgrades.deployProxy(MWXVestingFactory, [
          owner.address,
          scheduleManager.address,
          MAX_BATCH_CREATE,
          MAX_BATCH_RELEASE,
          badParams
        ])
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        vesting.initialize(
          owner.address,
          scheduleManager.address,
          MAX_BATCH_CREATE,
          MAX_BATCH_RELEASE,
          VESTING_PARAMS
        )
      ).to.be.reverted;
    });
  });

  describe("Role Management", function () {
    it("should allow owner to grant and revoke roles", async function () {
      const SCHEDULE_MANAGER_ROLE = await vesting.SCHEDULE_MANAGER_ROLE();
      const RELEASER_ROLE = await vesting.RELEASER_ROLE();
      const DEFAULT_ADMIN_ROLE = await vesting.DEFAULT_ADMIN_ROLE();

      // Grant SCHEDULE_MANAGER_ROLE to other
      await expect(vesting.connect(owner).grantRole(SCHEDULE_MANAGER_ROLE, other.address))
        .to.emit(vesting, "RoleGranted").withArgs(SCHEDULE_MANAGER_ROLE, other.address, owner.address);
      expect(await vesting.hasRole(SCHEDULE_MANAGER_ROLE, other.address)).to.be.true;

      // Revoke SCHEDULE_MANAGER_ROLE
      await expect(vesting.connect(owner).revokeRole(SCHEDULE_MANAGER_ROLE, other.address))
        .to.emit(vesting, "RoleRevoked").withArgs(SCHEDULE_MANAGER_ROLE, other.address, owner.address);
      expect(await vesting.hasRole(SCHEDULE_MANAGER_ROLE, other.address)).to.be.false;

      // Grant RELEASER_ROLE to other
      await expect(vesting.connect(owner).grantRole(RELEASER_ROLE, other.address))
        .to.emit(vesting, "RoleGranted");
      expect(await vesting.hasRole(RELEASER_ROLE, other.address)).to.be.true;

      // Grant DEFAULT_ADMIN_ROLE to other
      await expect(vesting.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, other.address))
        .to.emit(vesting, "RoleGranted");
      expect(await vesting.hasRole(DEFAULT_ADMIN_ROLE, other.address)).to.be.true;
    });

    it("should not allow non-admin to grant or revoke roles", async function () {
      const SCHEDULE_MANAGER_ROLE = await vesting.SCHEDULE_MANAGER_ROLE();
      await expect(
        vesting.connect(other).grantRole(SCHEDULE_MANAGER_ROLE, other.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
      await expect(
        vesting.connect(other).revokeRole(SCHEDULE_MANAGER_ROLE, scheduleManager.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should allow account to renounce its own role", async function () {
      const SCHEDULE_MANAGER_ROLE = await vesting.SCHEDULE_MANAGER_ROLE();
      await vesting.connect(owner).grantRole(SCHEDULE_MANAGER_ROLE, other.address);
      await expect(
        vesting.connect(other).renounceRole(SCHEDULE_MANAGER_ROLE, other.address)
      ).to.emit(vesting, "RoleRevoked").withArgs(SCHEDULE_MANAGER_ROLE, other.address, other.address);
      expect(await vesting.hasRole(SCHEDULE_MANAGER_ROLE, other.address)).to.be.false;
    });

    it("should not allow account to renounce role for another account", async function () {
      const SCHEDULE_MANAGER_ROLE = await vesting.SCHEDULE_MANAGER_ROLE();
      await vesting.connect(owner).grantRole(SCHEDULE_MANAGER_ROLE, other.address);
      await expect(
        vesting.connect(other).renounceRole(SCHEDULE_MANAGER_ROLE, owner.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlBadConfirmation");
    });

    it("should only allow owner to transfer ownership", async function () {
      await expect(
        vesting.connect(other).transferOwnership(other.address)
      ).to.be.revertedWithCustomError(vesting, "OwnableUnauthorizedAccount");
      await expect(
        vesting.connect(owner).transferOwnership(other.address)
      ).to.emit(vesting, "OwnershipTransferred").withArgs(owner.address, other.address);
      expect(await vesting.owner()).to.equal(other.address);
    });
  });

  describe("Contract Upgradeability", function () {
    it("Should support UUPS upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXVestingV2Factory =
        await ethers.getContractFactory("MWXVestingV2");
      const upgraded = await upgrades.upgradeProxy(
        await vesting.getAddress(),
        MWXVestingV2Factory,
        {
          call: {
            fn: "initializeV2",
            args: [],
          },
          unsafeAllow: ["missing-initializer-call"],
        }
      );

      const upgradedMWXVesting = upgraded as MWXVestingV2;

      // Verify state is preserved
      expect(await upgradedMWXVesting.owner()).to.equal(owner.address);
      expect(await upgradedMWXVesting.newFunction()).to.equal(
        "This is a new function in V2"
      );

      await expect(
        upgradedMWXVesting.initializeV2()
      ).to.be.revertedWithCustomError(vesting, "InvalidInitialization");
    });

    it("Should only allow owner to authorize upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXVestingV2Factory = await ethers.getContractFactory(
        "MWXVestingV2",
        beneficiary1
      );
      await expect(
        upgrades.upgradeProxy(
          await vesting.getAddress(),
          MWXVestingV2Factory,
          {
            call: {
              fn: "initializeV2",
              args: [],
            },
            unsafeAllow: ["missing-initializer-call"],
          }
        )
      ).to.be.revertedWithCustomError(vesting, "OwnableUnauthorizedAccount");
    });
  });

  describe("Set Default Vesting Params", function () {
    it("should allow schedule manager to set default vesting params", async function () {
      await expect(
        vesting.connect(scheduleManager).setVestingParameters(VESTING_PARAMS)
      ).to.emit(vesting, "VestingParametersSet");
      const params = await vesting.getDefaultVestingParams();
      expect(params.startTimestamp).to.equal(BigInt(VESTING_PARAMS.startTimestamp));
      expect(params.cliffDuration).to.equal(BigInt(VESTING_PARAMS.cliffDuration));
      expect(params.vestingDuration).to.equal(BigInt(VESTING_PARAMS.vestingDuration));
      expect(params.releaseIntervalDays).to.equal(BigInt(VESTING_PARAMS.releaseIntervalDays));
    });

    it("should revert if not schedule manager", async function () {
      await expect(
        vesting.connect(other).setVestingParameters(VESTING_PARAMS)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should revert if start timestamp is in the past", async function () {
      await expect(
        vesting.connect(scheduleManager).setVestingParameters({ ...VESTING_PARAMS, startTimestamp: 0 })
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });

    it("should revert if cliff duration is greater than vesting duration", async function () {
      await expect(
        vesting.connect(scheduleManager).setVestingParameters({ ...VESTING_PARAMS, cliffDuration: VESTING_PARAMS.vestingDuration + 1 })
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });

    it("should revert if release interval days is 0", async function () {
      await expect(
        vesting.connect(scheduleManager).setVestingParameters({ ...VESTING_PARAMS, releaseIntervalDays: 0 })
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });

    it("should revert if vesting duration less than release interval days", async function () {
      await expect(
        vesting.connect(scheduleManager).setVestingParameters({ 
          startTimestamp: VESTING_PARAMS.startTimestamp,
          cliffDuration: 0,
          vestingDuration: (VESTING_PARAMS.releaseIntervalDays - 1) * 86400,
          releaseIntervalDays: VESTING_PARAMS.releaseIntervalDays
        })
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });
  });

  describe("Set Vesting Token", function () {
    it("should revert if vesting token already set", async function () {
      await expect(
        vesting.connect(admin).setVestingToken(await token.getAddress())
      ).to.be.revertedWithCustomError(vesting, "VestingTokenAlreadySet");
    });

    it("should revert if not admin", async function () {
      await expect(
        vesting.connect(other).setVestingToken(await token.getAddress())
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should allow admin to set vesting token on a fresh instance", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      const freshVesting = (await upgrades.deployProxy(MWXVestingFactory, [
        owner.address,
        scheduleManager.address,
        MAX_BATCH_CREATE,
        MAX_BATCH_RELEASE,
        VESTING_PARAMS,
      ])) as unknown as MWXVesting;
      await freshVesting.waitForDeployment();

      const DEFAULT_ADMIN_ROLE = await freshVesting.DEFAULT_ADMIN_ROLE();
      await freshVesting.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, admin.address);

      const oldVestingToken = await freshVesting.vestingToken();
      await expect(
        freshVesting.connect(admin).setVestingToken(await token.getAddress())
      ).to.emit(freshVesting, "VestingTokenUpdated").withArgs(oldVestingToken, await token.getAddress());
      expect(await freshVesting.vestingToken()).to.equal(await token.getAddress());
    });

    it("should revert when setting zero address", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      const freshVesting = (await upgrades.deployProxy(MWXVestingFactory, [
        owner.address,
        scheduleManager.address,
        MAX_BATCH_CREATE,
        MAX_BATCH_RELEASE,
        VESTING_PARAMS,
      ])) as unknown as MWXVesting;
      await freshVesting.waitForDeployment();

      const DEFAULT_ADMIN_ROLE = await freshVesting.DEFAULT_ADMIN_ROLE();
      await freshVesting.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, admin.address);

      await expect(
        freshVesting.connect(admin).setVestingToken(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(freshVesting, "InvalidTokenAddress");
    });
  });

  describe("Vesting Schedule Creation", function () {
    let defaultParams: any;
    beforeEach(async function () {
      const params = await vesting.getDefaultVestingParams();
      defaultParams = {
        startTimestamp: Number(params.startTimestamp),
        cliffDuration: Number(params.cliffDuration),
        vestingDuration: Number(params.vestingDuration),
        releaseIntervalDays: Number(params.releaseIntervalDays),
      };
    });

    it("should allow schedule manager to create vesting schedule (default)", async function () {
      const total = ethers.parseUnits("1000", 6);
      const cliff = ethers.parseUnits("100", 6);
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address
        ], [total], [cliff])
      ).to.emit(vesting, "VestingScheduleCreated").withArgs(
        beneficiary1.address,
        total,
        defaultParams.startTimestamp,
        defaultParams.cliffDuration,
        defaultParams.vestingDuration,
        defaultParams.releaseIntervalDays * 86400
      );
      const schedule = await vesting.beneficiaryVestingSchedules(beneficiary1.address);
      expect(schedule.isActive).to.be.true;
      expect(schedule.totalVestedAmount + schedule.releaseAmountAtCliff).to.equal(total);
      expect(schedule.releaseAmountAtCliff).to.equal(cliff);
    });

    it("should allow schedule manager to create vesting schedule with custom params", async function () {
      const total = ethers.parseUnits("2000", 6);
      const cliff = ethers.parseUnits("200", 6);
      const customParams = [{
        startTimestamp: defaultParams.startTimestamp + 1000,
        cliffDuration: defaultParams.cliffDuration + 1000,
        vestingDuration: defaultParams.vestingDuration + 1000,
        releaseIntervalDays: defaultParams.releaseIntervalDays + 1,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule([
          beneficiary2.address
        ], [total], [cliff], customParams)
      ).to.emit(vesting, "VestingScheduleCreated").withArgs(
        beneficiary2.address,
        total,
        customParams[0].startTimestamp,
        customParams[0].cliffDuration,
        customParams[0].vestingDuration,
        (customParams[0].releaseIntervalDays) * 86400
      );
      const schedule = await vesting.beneficiaryVestingSchedules(beneficiary2.address);
      expect(schedule.isActive).to.be.true;
      expect(schedule.totalVestedAmount + schedule.releaseAmountAtCliff).to.equal(total);
      expect(schedule.releaseAmountAtCliff).to.equal(cliff);
    });

    it("should allow schedule manager to create vesting schedule with default params", async function () {
      const total = ethers.parseUnits("2000", 6);
      const cliff = ethers.parseUnits("200", 6);
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule([
          beneficiary2.address
        ], [total], [cliff], customParams)
      ).to.emit(vesting, "VestingScheduleCreated").withArgs(
        beneficiary2.address,
        total,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400
      );
      const schedule = await vesting.beneficiaryVestingSchedules(beneficiary2.address);
      expect(schedule.isActive).to.be.true;
      expect(schedule.totalVestedAmount + schedule.releaseAmountAtCliff).to.equal(total);
      expect(schedule.releaseAmountAtCliff).to.equal(cliff);
    });

    it("should allow batch creation up to maxBatchForCreateVestingSchedule", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address];
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6)];
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule(addrs, totals, cliffs)
      ).to.emit(vesting, "VestingScheduleCreated");
      for (let i = 0; i < addrs.length; i++) {
        const schedule = await vesting.beneficiaryVestingSchedules(addrs[i]);
        expect(schedule.isActive).to.be.true;
        expect(schedule.totalVestedAmount + schedule.releaseAmountAtCliff).to.equal(totals[i]);
        expect(schedule.releaseAmountAtCliff).to.equal(cliffs[i]);
      }
    });

    it("should allow create vesting schedule if recent beneficiary has no active schedule", async function () {
      const total = ethers.parseUnits("1000", 6);
      const cliff = ethers.parseUnits("100", 6);
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address
      ], [total], [cliff]);
      await expect(vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary2.address
      ], [total], [cliff])
      ).to.emit(vesting, "VestingScheduleCreated");

      await vesting.connect(scheduleManager).revokeVestingSchedule(beneficiary1.address);
      await expect(vesting.connect(scheduleManager).createVestingSchedule([beneficiary1.address], [total], [cliff]))
        .to.emit(vesting, "VestingScheduleCreated");
    });

    it("should revert if beneficiaries length is 0", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([], [], [])
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if beneficiaries length not equal to release cliff length", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([beneficiary1.address], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if beneficiaries length not equal to release cliff length", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([beneficiary1.address], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if batch exceeds maxBatchForCreateVestingSchedule", async function () {
      const addrs = [];
      const totals = [];
      const cliffs = [];
      for (let i = 0; i < MAX_BATCH_CREATE + 1; i++) {
        addrs.push(accounts[i].address);
        totals.push(ethers.parseUnits("1000", 6));
        cliffs.push(ethers.parseUnits("100", 6));
      }
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule(addrs, totals, cliffs)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if not schedule manager", async function () {
      await expect(
        vesting.connect(other).createVestingSchedule([
          beneficiary1.address
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6)])
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should revert if array lengths mismatch", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address, beneficiary2.address
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if beneficiary is zero address", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          ethers.ZeroAddress
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidAddress");
    });

    it("should revert if total amount is zero", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address
        ], [0], [ethers.parseUnits("100", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
    });

    it("should revert if release amount at cliff >= total amount", async function () {
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("1000", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("2000", 6)])
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
    });

    it("should revert if vesting params are invalid (e.g. cliff > vesting duration)", async function () {
      const badParams = [{
        startTimestamp: defaultParams.startTimestamp,
        cliffDuration: defaultParams.vestingDuration + 1,
        vestingDuration: defaultParams.vestingDuration,
        releaseIntervalDays: defaultParams.releaseIntervalDays,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule([
          beneficiary1.address
        ], [ethers.parseUnits("1000", 6)], [ethers.parseUnits("100", 6)], badParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidVestingParams");
    });

    it("should revert if beneficiary already has an active schedule", async function () {
      const total = ethers.parseUnits("1000", 6);
      const cliff = ethers.parseUnits("100", 6);
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address
      ], [total], [cliff]);
      await expect(
        vesting.connect(scheduleManager).createVestingSchedule([
          beneficiary1.address
        ], [total], [cliff])
      ).to.be.revertedWithCustomError(vesting, "InvalidSchedule");
    });

    it("should not allow batch creation if exceeds maxBatchForCreateVestingSchedule", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address, other.address, owner.address, scheduleManager.address];
      const totals = [
        ethers.parseUnits("1000", 6), 
        ethers.parseUnits("2000", 6), 
        ethers.parseUnits("3000", 6), 
        ethers.parseUnits("4000", 6), 
        ethers.parseUnits("5000", 6),
        ethers.parseUnits("6000", 6),
      ];
      const cliffs = [
        ethers.parseUnits("100", 6), 
        ethers.parseUnits("200", 6), 
        ethers.parseUnits("300", 6), 
        ethers.parseUnits("400", 6), 
        ethers.parseUnits("500", 6),
        ethers.parseUnits("600", 6),
      ];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule(addrs, totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should not allow batch creation if vesting params not matching length", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address, other.address];
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6), ethers.parseUnits("4000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6), ethers.parseUnits("400", 6)];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule(addrs, totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should not allow batch creation if release amount at cliff not matching length", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address, other.address];
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6), ethers.parseUnits("4000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6)];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule(addrs, totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should not allow batch creation if total amount not matching length", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address, other.address];
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6), ethers.parseUnits("400", 6)];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule(addrs, totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should not allow batch creation if beneficiary length is 0", async function () {
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6)];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }, {
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(scheduleManager).createVestingScheduleWithCustomSchedule([], totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should not allow batch creation if not schedule manager", async function () {
      const addrs = [beneficiary1.address, beneficiary2.address, beneficiary3.address, other.address];
      const totals = [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6), ethers.parseUnits("3000", 6), ethers.parseUnits("4000", 6)];
      const cliffs = [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6), ethers.parseUnits("300", 6), ethers.parseUnits("400", 6)];
      const customParams = [{
        startTimestamp: 0,
        cliffDuration: 0,
        vestingDuration: 0,
        releaseIntervalDays: 0,
      }];
      await expect(
        vesting.connect(beneficiary1).createVestingScheduleWithCustomSchedule(addrs, totals, cliffs, customParams)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Claiming and Releasing", function () {
    let total: bigint;
    let cliff: bigint;
    let now: number;
    beforeEach(async function () {
      now = await time.latest();
      total = ethers.parseUnits("1200", 6);
      cliff = ethers.parseUnits("200", 6);
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address
      ], [total], [cliff]);
    });

    it("should not allow claim before cliff", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp - 10);
      await expect(
        vesting.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
    });

    it("should revert claim if vesting token not set", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      const vestingNoToken = (await upgrades.deployProxy(MWXVestingFactory, [
        owner.address,
        scheduleManager.address,
        MAX_BATCH_CREATE,
        MAX_BATCH_RELEASE,
        VESTING_PARAMS,
      ])) as unknown as MWXVesting;
      await vestingNoToken.waitForDeployment();

      // Create schedule without setting vesting token
      const total2 = ethers.parseUnits("1000", 6);
      const cliff2 = ethers.parseUnits("100", 6);
      await vestingNoToken.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address,
      ], [total2], [cliff2]);

      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vestingNoToken.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vestingNoToken, "VestingTokenNotSet");
    });

    it("should allow claim at cliff for cliff amount", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      const before = await token.balanceOf(beneficiary1.address);
      await expect(vesting.connect(beneficiary1).claim()).to.emit(vesting, "TokensClaimed").withArgs(beneficiary1.address, cliff);
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(cliff);
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);
    });

    it("should allow claim after cliff for interval amount", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400);
      
      // 1000 / 13 = 76.923076923076923076 + 200 = 276.923076923076923076
      const expected = ((total - cliff) / 13n) + cliff;
      const before = await token.balanceOf(beneficiary1.address);
      const releasableAmount = await vesting.releasableAmount(beneficiary1.address);
      await vesting.connect(beneficiary1).claim();
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(expected);
      expect(expected).to.equal(releasableAmount);
    });

    it("should revert claim with ERC20InsufficientBalance when contract has insufficient tokens", async function () {
      const MWXVestingFactory = await ethers.getContractFactory("MWXVesting");
      const vestingNoFunds = (await upgrades.deployProxy(MWXVestingFactory, [
        owner.address,
        scheduleManager.address,
        MAX_BATCH_CREATE,
        MAX_BATCH_RELEASE,
        VESTING_PARAMS,
      ])) as unknown as MWXVesting;
      await vestingNoFunds.waitForDeployment();

      const DEFAULT_ADMIN_ROLE = await vestingNoFunds.DEFAULT_ADMIN_ROLE();
      await vestingNoFunds.connect(owner).grantRole(DEFAULT_ADMIN_ROLE, admin.address);
      await vestingNoFunds.connect(admin).setVestingToken(await token.getAddress());

      const total2 = ethers.parseUnits("1000", 6);
      const cliff2 = ethers.parseUnits("100", 6);
      await vestingNoFunds.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address,
      ], [total2], [cliff2]);

      // Do NOT fund vestingNoFunds with tokens
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vestingNoFunds.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vestingNoFunds, "ERC20InsufficientBalance");
    });

    it("should allow claim after cliff for interval amount for 3 months with cliff", async function () {
        await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
        await vesting.connect(beneficiary1).claim();
        expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
          total - cliff,
          cliff,
          cliff,
          VESTING_PARAMS.startTimestamp,
          VESTING_PARAMS.cliffDuration,
          VESTING_PARAMS.vestingDuration,
          VESTING_PARAMS.releaseIntervalDays * 86400,
          true,
        ]);
    
        await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 3);
        
        // (1000 * 3) / 13 = 230.769230769230769230
        const expected = ((total - cliff) * 3n / 13n);
        const before = await token.balanceOf(beneficiary1.address);
        const releasableAmount = await vesting.releasableAmount(beneficiary1.address);
        await vesting.connect(beneficiary1).claim();
        const after = await token.balanceOf(beneficiary1.address);
        expect(after - before).to.equal(expected);
        expect(expected).to.equal(releasableAmount);
    });

    it("should allow claim after vesting for all remaining after claiming cliff and 2 months then 4 months then the rest", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);

      // 2 months
      // (1000 * 2) / 13 = 153.846153846153846153
      const expectedFor2Months = ((total - cliff) * 2n / 13n);
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 2);
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        expectedFor2Months + cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);

      // 4 months
      // (1000 * 4) / 13 - 153.846153846153846153 = 153.846153846153846153
      const expectedFor4Months = ((total - cliff) * 4n / 13n) - expectedFor2Months;
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 4);
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        expectedFor4Months + expectedFor2Months + cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);

      // rest of the vesting duration
      // 1000 - 153.846153846153846153 - 153.846153846153846153 = 692.307692307692307694
      const expectedForRest = total - cliff - expectedFor2Months - expectedFor4Months;
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.vestingDuration + VESTING_PARAMS.cliffDuration + 1);
      const before = await token.balanceOf(beneficiary1.address);
      await vesting.connect(beneficiary1).claim();
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(expectedForRest);
      expect(0).to.equal(await vesting.releasableAmount(beneficiary1.address));
    });

    it("should allow claim after cliff for interval amount for 3 months with cliff", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);
  
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 3);
      
      // (1000 * 3) / 13 = 230.769230769230769230
      const expected = ((total - cliff) * 3n / 13n);
      const before = await token.balanceOf(beneficiary1.address);
      const releasableAmount = await vesting.releasableAmount(beneficiary1.address);
      await vesting.connect(beneficiary1).claim();
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(expected);
      expect(expected).to.equal(releasableAmount);
    });

    it("should allow claim after vesting for all remaining after claiming cliff and 12 months then the rest", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);

      // 12 months + 2 days
      // (1000 * 12) / 13 = 923.076923076923076923
      const expectedFor12Months = ((total - cliff) * 12n / 13n);
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 12 + (2 * 86400));
      await vesting.connect(beneficiary1).claim();
      expect(await vesting.getVestingSchedule(beneficiary1.address)).to.deep.equal([
        total - cliff,
        cliff,
        expectedFor12Months + cliff,
        VESTING_PARAMS.startTimestamp,
        VESTING_PARAMS.cliffDuration,
        VESTING_PARAMS.vestingDuration,
        VESTING_PARAMS.releaseIntervalDays * 86400,
        true,
      ]);

      // rest of the vesting duration
      // 1000 - 923.076923076923076923 = 76.923076923076923077
      const expectedForRest = total - cliff - expectedFor12Months;
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.vestingDuration + VESTING_PARAMS.cliffDuration + 1);
      const before = await token.balanceOf(beneficiary1.address);
      await vesting.connect(beneficiary1).claim();
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(expectedForRest);
      expect(0).to.equal(await vesting.releasableAmount(beneficiary1.address));
    });

    it("should not allow claim if nothing claimable", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      await expect(
        vesting.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
    });

    it("should not allow claim after schedule is revoked", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      await vesting.connect(scheduleManager).revokeVestingSchedule(beneficiary1.address);
      await expect(
        vesting.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vesting, "ScheduleNotActive");
      expect(await vesting.releasableAmount(beneficiary1.address)).to.equal(0);
    });

    it("should not allow claim if schedule time not reached after cliff duration", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration - 1000);
      await expect(
        vesting.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
      expect(await vesting.releasableAmount(beneficiary1.address)).to.equal(0);
    });

    it("should not allow non-beneficiary to claim", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(other).claim()
      ).to.be.revertedWithCustomError(vesting, "ScheduleNotActive");
    });

    it("should allow releaser to release for beneficiary", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      const before = await token.balanceOf(beneficiary1.address);
      await expect(
        vesting.connect(releaser).release(beneficiary1.address)
      ).to.emit(vesting, "TokensClaimed").withArgs(beneficiary1.address, cliff);
      const after = await token.balanceOf(beneficiary1.address);
      expect(after - before).to.equal(cliff);
    });

    it("should not allow non-releaser to release for beneficiary", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(other).release(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should not allow release from non schedule manager", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(other).release(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should not allow release when paused", async function () {
      await vesting.connect(owner).pause();
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(releaser).release(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "EnforcedPause");
    });

    it("should allow batch release up to maxBatchForRelease", async function () {
      // Create schedules for 2 beneficiaries
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary2.address
      ], [total], [cliff]);
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(releaser).releaseBatch([beneficiary1.address, beneficiary2.address])
      ).to.emit(vesting, "TokensClaimed");
    });

    it("should not allow release batch if not schedule manager", async function () {
      // Create schedules for 2 beneficiaries
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary2.address
      ], [total], [cliff]);
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(other).releaseBatch([beneficiary1.address, beneficiary2.address])
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should not allow release batch when paused", async function () {
      // Create schedules for 2 beneficiaries
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary2.address
      ], [total], [cliff]);
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(owner).pause();
      await expect(
        vesting.connect(releaser).releaseBatch([beneficiary1.address, beneficiary2.address])
      ).to.be.revertedWithCustomError(vesting, "EnforcedPause");
    });

    it("should revert if batch exceeds maxBatchForRelease", async function () {
      const addrs = [];
      for (let i = 0; i < MAX_BATCH_RELEASE + 1; i++) {
        addrs.push(accounts[i].address);
        await vesting.connect(scheduleManager).createVestingSchedule([
          accounts[i].address
        ], [total], [cliff]);
      }
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(releaser).releaseBatch(addrs)
      ).to.be.revertedWithCustomError(vesting, "InvalidParameterLength");
    });

    it("should revert if paused (claim)", async function () {
      await vesting.connect(owner).pause();
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(beneficiary1).claim()
      ).to.be.revertedWithCustomError(vesting, "EnforcedPause");
    });

    it("should revert if paused (release)", async function () {
      await vesting.connect(owner).pause();
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await expect(
        vesting.connect(releaser).release(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "EnforcedPause");
    });
  });

  describe("Revoking Schedules", function () {
    let total: bigint;
    let cliff: bigint;
    beforeEach(async function () {
      total = ethers.parseUnits("1000", 6);
      cliff = ethers.parseUnits("100", 6);
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address
      ], [total], [cliff]);
    });

    it("should allow schedule manager to revoke an active schedule", async function () {
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      // Claim cliff
      await vesting.connect(beneficiary1).claim();
      const claimed = await vesting.beneficiaryVestingSchedules(beneficiary1.address).then(s => s.claimedAmount);
      const expectedUnreleased = total - claimed;
      await expect(
        vesting.connect(scheduleManager).revokeVestingSchedule(beneficiary1.address)
      ).to.emit(vesting, "VestingScheduleRevoked").withArgs(
        beneficiary1.address,
        claimed,
        expectedUnreleased
      );
      const schedule = await vesting.beneficiaryVestingSchedules(beneficiary1.address);
      expect(schedule.isActive).to.be.false;
    });

    it("should not allow non-schedule manager to revoke", async function () {
      await expect(
        vesting.connect(other).revokeVestingSchedule(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should not allow revoking a non-active schedule", async function () {
      await vesting.connect(scheduleManager).revokeVestingSchedule(beneficiary1.address);
      await expect(
        vesting.connect(scheduleManager).revokeVestingSchedule(beneficiary1.address)
      ).to.be.revertedWithCustomError(vesting, "ScheduleNotActive");
    });
  });

  describe("Pausing/Unpausing", function () {
    it("should allow admin to pause and unpause", async function () {
      await expect(vesting.connect(admin).pause())
        .to.emit(vesting, "Paused").withArgs(admin.address);
      expect(await vesting.paused()).to.be.true;
      await expect(vesting.connect(admin).unpause())
        .to.emit(vesting, "Unpaused").withArgs(admin.address);
      expect(await vesting.paused()).to.be.false;
    });

    it("should not allow non-admin to pause or unpause", async function () {
      await expect(vesting.connect(other).pause())
        .to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
      await vesting.connect(admin).pause();
      await expect(vesting.connect(other).unpause())
        .to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should revert if already paused", async function () {
      await vesting.connect(admin).pause();
      await expect(vesting.connect(admin).pause())
        .to.be.revertedWithCustomError(vesting, "EnforcedPause");
    });

    it("should revert if already unpaused", async function () {
      await expect(vesting.connect(admin).unpause())
        .to.be.revertedWithCustomError(vesting, "ExpectedPause");
    });
  });

  describe("Foreign Token and ETH Withdrawal", function () {
    let mockToken: MockERC20;
    beforeEach(async function () {
      // Deploy a new mock token and send to vesting contract
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      mockToken = await MockERC20Factory.deploy("Mock2", "MOCK2", ethers.parseUnits("1000000", 6));
      await mockToken.waitForDeployment();
      await mockToken.transfer(await vesting.getAddress(), ethers.parseUnits("1000", 6));
    });

    it("should allow owner to withdraw ERC20 tokens", async function () {
      const withdrawAmount = ethers.parseUnits("500", 6);
      const before = await mockToken.balanceOf(owner.address);
      await expect(
        vesting.connect(owner).withdrawForeignToken(await mockToken.getAddress(), owner.address, withdrawAmount)
      ).to.emit(vesting, "WithdrawForeignToken").withArgs(await mockToken.getAddress(), owner.address, withdrawAmount);
      const after = await mockToken.balanceOf(owner.address);
      expect(after - before).to.equal(withdrawAmount);
    });

    it("should allow owner to withdraw ETH", async function () {
      // Send ETH to contract
      await owner.sendTransaction({ to: await vesting.getAddress(), value: ethers.parseEther("1") });
      const withdrawAmount = ethers.parseEther("0.5");
      const before = await ethers.provider.getBalance(owner.address);
      await expect(
        vesting.connect(owner).withdrawForeignToken(ethers.ZeroAddress, owner.address, withdrawAmount)
      ).to.emit(vesting, "WithdrawForeignToken").withArgs(ethers.ZeroAddress, owner.address, withdrawAmount);
      // (ETH balance check skipped due to gas cost variability)
    });

    it("should not allow non-owner to withdraw", async function () {
      await expect(
        vesting.connect(other).withdrawForeignToken(await mockToken.getAddress(), other.address, ethers.parseUnits("100", 6))
      ).to.be.revertedWithCustomError(vesting, "OwnableUnauthorizedAccount");
    });

    it("should not allow withdraw vesting token", async function () {
      await expect(
        vesting.connect(owner).withdrawForeignToken(await vesting.vestingToken(), owner.address, ethers.parseUnits("100", 6))
      ).to.be.revertedWithCustomError(vesting, "InvalidTokenAddress");
    });

    it("should revert if recipient is zero address", async function () {
      await expect(
        vesting.connect(owner).withdrawForeignToken(await mockToken.getAddress(), ethers.ZeroAddress, ethers.parseUnits("100", 6))
      ).to.be.revertedWithCustomError(vesting, "InvalidAddress");
    });

    it("should revert if amount is zero", async function () {
      await expect(
        vesting.connect(owner).withdrawForeignToken(await mockToken.getAddress(), owner.address, 0)
      ).to.be.revertedWithCustomError(vesting, "InvalidAmount");
    });

    it("should revert if insufficient ERC20 balance", async function () {
      const tooMuch = ethers.parseUnits("10000000", 6);
      await expect(
        vesting.connect(owner).withdrawForeignToken(await mockToken.getAddress(), owner.address, tooMuch)
      ).to.be.revertedWithCustomError(vesting, "ERC20InsufficientBalance");
    });

    it("should revert if insufficient ETH balance", async function () {
      const tooMuch = ethers.parseEther("1000");
      await expect(
        vesting.connect(owner).withdrawForeignToken(ethers.ZeroAddress, owner.address, tooMuch)
      ).to.be.revertedWithCustomError(vesting, "InsufficientBalance");
    });
  });

  describe("Batch Operations and Miscellaneous", function () {
    beforeEach(async function () {
      await vesting.connect(scheduleManager).createVestingSchedule([
        beneficiary1.address, beneficiary2.address
      ], [ethers.parseUnits("1000", 6), ethers.parseUnits("2000", 6)], [ethers.parseUnits("100", 6), ethers.parseUnits("200", 6)]);
    });

    it("should allow admin to set maxBatchForCreateVestingSchedule", async function () {
      await expect(vesting.connect(admin).setMaxBatchForCreateVestingSchedule(10))
        .to.emit(vesting, "MaxBatchForCreateVestingScheduleUpdated").withArgs(10);
      expect(await vesting.maxBatchForCreateVestingSchedule()).to.equal(10);
    });

    it("should allow admin to set maxBatchForRelease", async function () {
      await expect(vesting.connect(admin).setMaxBatchForRelease(10))
        .to.emit(vesting, "MaxBatchForReleaseUpdated").withArgs(10);
      expect(await vesting.maxBatchForRelease()).to.equal(10);
    });

    it("should not allow non-admin to set maxBatchForCreateVestingSchedule", async function () {
      await expect(vesting.connect(other).setMaxBatchForCreateVestingSchedule(10))
        .to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should not allow non-admin to set maxBatchForRelease", async function () {
      await expect(vesting.connect(other).setMaxBatchForRelease(10))
        .to.be.revertedWithCustomError(vesting, "AccessControlUnauthorizedAccount");
    });

    it("should get beneficiaries with pagination", async function () {
      const [result, total] = await vesting.getBeneficiaries(0, 1);
      expect(result.length).to.equal(1);
      expect(total).to.equal(2n);
      const [result2, total2] = await vesting.getBeneficiaries(1, 2);
      expect(result2.length).to.equal(1);
      expect(total2).to.equal(2n);
      const [empty, total3] = await vesting.getBeneficiaries(2, 2);
      expect(empty.length).to.equal(0);
      expect(total3).to.equal(2n);
    });

    it("should get beneficiary vesting schedules with pagination", async function () {
      const [result, total] = await vesting.getBeneficiaryVestingSchedules(0, 1);
      expect(result.length).to.equal(1);
      expect(total).to.equal(2n);
      const [result2, total2] = await vesting.getBeneficiaryVestingSchedules(1, 2);
      expect(result2.length).to.equal(1);
      expect(total2).to.equal(2n);
      const [empty, total3] = await vesting.getBeneficiaryVestingSchedules(2, 2);
      expect(empty.length).to.equal(0);
      expect(total3).to.equal(2n);
    });

    it("should get beneficiary claim history with pagination", async function () {
      // No claims yet
      const [result, total] = await vesting.getBeneficiaryClaimHistory(beneficiary1.address, 0, 10);
      expect(result.length).to.equal(0);
      expect(total).to.equal(0n);
      // Make a claim
      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration);
      await vesting.connect(beneficiary1).claim();
      const [result2, total2] = await vesting.getBeneficiaryClaimHistory(beneficiary1.address, 0, 10);
      expect(result2.length).to.equal(1);
      expect(total2).to.equal(1n);

      await time.increaseTo(VESTING_PARAMS.startTimestamp + VESTING_PARAMS.cliffDuration + VESTING_PARAMS.releaseIntervalDays * 86400 * 1);
      await vesting.connect(beneficiary1).claim();
      const [result3, total3] = await vesting.getBeneficiaryClaimHistory(beneficiary1.address, 0, 1);
      expect(result3.length).to.equal(1);
      expect(total3).to.equal(2n);

      const [empty2, total4] = await vesting.getBeneficiaryClaimHistory(beneficiary1.address, 2, 10);
      expect(empty2.length).to.equal(0);
      expect(total4).to.equal(2n);
    });

    it("should get all total vested amount (cliff + linear)", async function () {
      const total = await vesting.getAllTotalVestedAmount();
      expect(total).to.equal(
        ethers.parseUnits("1000", 6) +
        ethers.parseUnits("2000", 6)
      );
    });

    it("should get beneficiaries count", async function () {
      const count = await vesting.getBeneficiariesCount();
      expect(count).to.equal(2n);
    });

    it("should get default vesting params", async function () {
      const params = await vesting.getDefaultVestingParams();
      expect(Number(params.startTimestamp)).to.be.greaterThan(0);
      expect(Number(params.cliffDuration)).to.be.greaterThan(0);
      expect(Number(params.vestingDuration)).to.be.greaterThan(0);
      expect(Number(params.releaseIntervalDays)).to.be.greaterThan(0);
    });
  });
}) 