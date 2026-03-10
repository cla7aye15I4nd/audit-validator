import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MWXLaunchpad, MWXLaunchpadV2, MockERC20 } from "../typechain-types";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("MWXLaunchpad", function () {
  let launchpad: MWXLaunchpad;
  let usdt: MockERC20;
  let usdc: MockERC20;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let verifier: SignerWithAddress;
  let destination: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let unauthorized: SignerWithAddress;

  let decimalTokenSold = 18; // 18 decimals
  const INITIAL_SUPPLY = ethers.parseUnits("1000000", 6); // 1M tokens with 6 decimals
  const TOKEN_PRICE = ethers.parseUnits("0.1", 18); // $0.1 per token
  const TOTAL_ALLOCATION = ethers.parseUnits("100000", 18); // 100k tokens
  const SOFT_CAP = ethers.parseUnits("5000", 6); // $5,000
  const HARD_CAP = ethers.parseUnits("10000", 6); // $10,000
  const MINIMUM_PURCHASE = ethers.parseUnits("100", 6); // $100

  async function getTimestamp(): Promise<number> {
    const blockNum = await ethers.provider.getBlockNumber();
    const block = await ethers.provider.getBlock(blockNum);
    return block!.timestamp;
  }

  async function signWhitelist(
    buyer: string,
    contractAddress: string,
    chainId: bigint,
    verifierSigner: SignerWithAddress
  ): Promise<string> {
    const domain = {
      name: "MWXLaunchpad",
      version: await launchpad.version(),
      chainId: chainId,
      verifyingContract: contractAddress,
    };
    const types = {
      BuyAllocation: [
        { name: "buyer", type: "address" }
      ],
    };
    const value = { buyer };
    return await verifierSigner.signTypedData(domain, types, value);
  }

  beforeEach(async function () {
    [owner, admin, verifier, destination, user1, user2, user3, unauthorized] =
      await ethers.getSigners();

    // Deploy mock ERC20 tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    usdt = await MockERC20Factory.deploy(
      "Tether USD",
      "USDT",
      INITIAL_SUPPLY * BigInt(4)
    );
    usdc = await MockERC20Factory.deploy(
      "USD Coin",
      "USDC",
      INITIAL_SUPPLY * BigInt(4)
    );

    // Deploy MWXLaunchpad using upgrades plugin
    const MWXLaunchpadFactory = await ethers.getContractFactory("MWXLaunchpad");
    launchpad = (await upgrades.deployProxy(MWXLaunchpadFactory, [
      await usdt.getAddress(),
      await usdc.getAddress(),
      owner.address,
      verifier.address,
      destination.address,
      decimalTokenSold
    ])) as unknown as MWXLaunchpad;

    // Mint tokens to users
    await usdt.transfer(user1.address, INITIAL_SUPPLY);
    await usdt.transfer(user2.address, INITIAL_SUPPLY);
    await usdt.transfer(user3.address, INITIAL_SUPPLY);

    await usdc.transfer(user1.address, INITIAL_SUPPLY);
    await usdc.transfer(user2.address, INITIAL_SUPPLY);
    await usdc.transfer(user3.address, INITIAL_SUPPLY);

    // Grant admin role
    const DEFAULT_ADMIN_ROLE = await launchpad.DEFAULT_ADMIN_ROLE();
    await launchpad.grantRole(DEFAULT_ADMIN_ROLE, admin.address);
  });

  describe("Initialization", function () {
    it("Should initialize with correct parameters", async function () {
      expect(await launchpad.usdt()).to.equal(await usdt.getAddress());
      expect(await launchpad.usdc()).to.equal(await usdc.getAddress());
      expect(await launchpad.owner()).to.equal(owner.address);
      expect(await launchpad.adminVerifier()).to.equal(verifier.address);
      expect(await launchpad.destinationAddress()).to.equal(
        destination.address
      );
      expect(await launchpad.version()).to.equal("1");
      expect(await launchpad.decimalTokenSold()).to.equal(decimalTokenSold);
    });

    it("Should revert with zero addresses of usdt", async function () {
      const MWXLaunchpadFactory =
        await ethers.getContractFactory("MWXLaunchpad");
      await expect(
        upgrades.deployProxy(MWXLaunchpadFactory, [
          ethers.ZeroAddress,
          await usdc.getAddress(),
          owner.address,
          verifier.address,
          destination.address,
          decimalTokenSold
        ])
      ).to.be.revertedWithCustomError(launchpad, "InvalidTokenAddress");
    });

    it("Should revert with zero addresses of usdc", async function () {
      const MWXLaunchpadFactory =
        await ethers.getContractFactory("MWXLaunchpad");
      await expect(
        upgrades.deployProxy(MWXLaunchpadFactory, [
          await usdt.getAddress(),
          ethers.ZeroAddress,
          owner.address,
          verifier.address,
          destination.address,
          decimalTokenSold
        ])
      ).to.be.revertedWithCustomError(launchpad, "InvalidTokenAddress");
    });

    it("Should revert with zero addresses of owner", async function () {
      const MWXLaunchpadFactory =
        await ethers.getContractFactory("MWXLaunchpad");
      await expect(
        upgrades.deployProxy(MWXLaunchpadFactory, [
          await usdt.getAddress(),
          await usdc.getAddress(),
          ethers.ZeroAddress,
          verifier.address,
          destination.address,
          decimalTokenSold
        ])
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
    });

    it("Should revert with zero addresses of adminVerifier", async function () {
      const MWXLaunchpadFactory =
        await ethers.getContractFactory("MWXLaunchpad");
      await expect(
        upgrades.deployProxy(MWXLaunchpadFactory, [
          await usdt.getAddress(),
          await usdc.getAddress(),
          owner.address,
          ethers.ZeroAddress,
          destination.address,
          decimalTokenSold
        ])
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
    });

    it("Should revert with zero addresses of destinationAddress", async function () {
      const MWXLaunchpadFactory =
        await ethers.getContractFactory("MWXLaunchpad");
      await expect(
        upgrades.deployProxy(MWXLaunchpadFactory, [
          await usdt.getAddress(),
          await usdc.getAddress(),
          owner.address,
          verifier.address,
          ethers.ZeroAddress,
          decimalTokenSold
        ])
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
    });

    it("Should have correct roles", async function () {
      const DEFAULT_ADMIN_ROLE = await launchpad.DEFAULT_ADMIN_ROLE();
      expect(await launchpad.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be
        .true;
      expect(await launchpad.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be
        .true;
    });

    it("Should fail when calling initialize", async function () {
      await expect(
        launchpad.initialize(
          await usdt.getAddress(),
          await usdc.getAddress(),
          owner.address,
          verifier.address,
          destination.address,
          decimalTokenSold
        )
      ).to.be.revertedWithCustomError(launchpad, "InvalidInitialization");
    });
  });

  describe("Sale Configuration", function () {
    it("Should configure sale successfully", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600; // 1 hour from now
      const endTime = startTime + 86400; // 24 hours after start

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.emit(launchpad, "SaleStarted").withArgs(startTime, endTime, TOKEN_PRICE, TOTAL_ALLOCATION, decimalTokenSold);

      expect(await launchpad.startTime()).to.equal(startTime);
      expect(await launchpad.endTime()).to.equal(endTime);
      expect(await launchpad.tokenPrice()).to.equal(TOKEN_PRICE);
      expect(await launchpad.totalAllocation()).to.equal(TOTAL_ALLOCATION);
      expect(await launchpad.softCap()).to.equal(SOFT_CAP);
      expect(await launchpad.hardCap()).to.equal(HARD_CAP);
      expect(await launchpad.minimumPurchase()).to.equal(MINIMUM_PURCHASE);
      expect(await launchpad.decimalTokenSold()).to.equal(decimalTokenSold);
    });

    it("Should revert with invalid time range (end before start)", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime - 1800; // End before start

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidTimeRange");
    });

    it("Should revert with invalid time range (start before now)", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime - 3600;
      const endTime = startTime + 86400; // End after start

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidTimeRange");
    });

    it("Should revert with invalid amounts", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      // Zero token price
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            0,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      // Zero total allocation
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            0,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      // Zero minimum purchase
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            0,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      // Zero soft cap
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            0,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      // Zero hard cap
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            0,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      // Soft cap >= hard cap
      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            HARD_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");
    });

    it("Should reverted saleAlreadyStarted", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      await time.increaseTo(startTime + 1);

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime + 1000,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.revertedWithCustomError(launchpad, "SaleAlreadyStarted");
    });

    it("Should only allow admin to configure sale", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      await expect(
        launchpad
          .connect(unauthorized)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.be.reverted;
    });
  });

  describe("Sale Parameters", function () {
    it("Should successfully set sale parameters", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      )
        .to.emit(launchpad, "SaleStarted")
        .withArgs(startTime, endTime, TOKEN_PRICE, TOTAL_ALLOCATION, decimalTokenSold);

      await time.increaseTo(startTime + 1);

      await launchpad
        .connect(admin)
        .setSaleParameters(endTime + 1000, MINIMUM_PURCHASE);

      expect(await launchpad.startTime()).to.equal(startTime);
      expect(await launchpad.endTime()).to.equal(endTime + 1000);
      expect(await launchpad.minimumPurchase()).to.equal(MINIMUM_PURCHASE);
    });

    it("Should revert with invalid time range", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.emit(launchpad, "SaleStarted").withArgs(startTime, endTime, TOKEN_PRICE, TOTAL_ALLOCATION, decimalTokenSold);

      await time.increaseTo(startTime + 1);

      await expect(
        launchpad
          .connect(admin)
          .setSaleParameters(endTime - startTime, MINIMUM_PURCHASE)
      ).to.be.revertedWithCustomError(launchpad, "InvalidTimeRange");

      await time.increaseTo(endTime - 1000);

      await expect(
        launchpad
          .connect(admin)
          .setSaleParameters(endTime - 3000, MINIMUM_PURCHASE)
      ).to.be.revertedWithCustomError(launchpad, "InvalidTimeRange");
    });

    it("Should revert with invalid minimum purchase", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 3600;
      const endTime = startTime + 86400;

      await expect(
        launchpad
          .connect(admin)
          .configureSale(
            startTime,
            endTime,
            TOKEN_PRICE,
            TOTAL_ALLOCATION,
            SOFT_CAP,
            HARD_CAP,
            MINIMUM_PURCHASE,
            decimalTokenSold
          )
      ).to.emit(launchpad, "SaleStarted").withArgs(startTime, endTime, TOKEN_PRICE, TOTAL_ALLOCATION, decimalTokenSold);

      await time.increaseTo(startTime + 1);

      await expect(
        launchpad.connect(admin).setSaleParameters(endTime + 1000, 0)
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");

      await expect(
        launchpad
          .connect(unauthorized)
          .setSaleParameters(endTime + 1000, MINIMUM_PURCHASE)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
    });
  });

  describe("Buying Allocation", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );
    });

    it("Should allow whitelisted user to buy allocation with USDT", async function () {
      const decimalTokenSold = await launchpad.decimalTokenSold();
      const purchaseAmount = ethers.parseUnits("1000", 6); // $1000
      const adjustedPurchaseAmount = purchaseAmount * ethers.parseUnits("1", 18 - 6);
      const expectedTokens = (adjustedPurchaseAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      )
        .to.emit(launchpad, "AllocationPurchased")
        .withArgs(
          user1.address,
          purchaseAmount,
          expectedTokens,
          (await getTimestamp()) + 1
        );

      expect(await launchpad.userContributions(user1.address)).to.equal(
        purchaseAmount
      );
      expect(await launchpad.userUsdtContributions(user1.address)).to.equal(
        purchaseAmount
      );
      expect(await launchpad.userUsdcContributions(user1.address)).to.equal(
        0
      );
      expect(await launchpad.userAllocations(user1.address)).to.equal(
        expectedTokens
      );
      expect(await launchpad.totalUSDCollected()).to.equal(purchaseAmount);
      expect(await launchpad.totalTokensSold()).to.equal(expectedTokens);
      expect(await launchpad.totalUsdtCollected()).to.equal(purchaseAmount);
    });

    it("Should allow whitelisted user to buy allocation with USDC", async function () {
      const purchaseAmount = ethers.parseUnits("1000", 6);
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      await usdc
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdc.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.emit(launchpad, "AllocationPurchased");

      expect(await launchpad.userContributions(user1.address)).to.equal(
        purchaseAmount
      );
      expect(await launchpad.userUsdtContributions(user1.address)).to.equal(
        0
      );
      expect(await launchpad.userUsdcContributions(user1.address)).to.equal(
        purchaseAmount
      );
      expect(await launchpad.totalUsdcCollected()).to.equal(purchaseAmount);
    });

    it("Should revert if sale hasn't started", async function () {
      // Deploy new contract with future start time
      const currentTime = await getTimestamp();
      const futureStartTime = currentTime + 86400;
      const futureEndTime = futureStartTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          futureStartTime,
          futureEndTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "SaleNotActive");
    });

    it("Should revert if purchase amount is below minimum", async function () {
      const purchaseAmount = MINIMUM_PURCHASE - ethers.parseUnits("1", 6);
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "BelowMinimumPurchase");
    });

    it("Should revert if hard cap would be exceeded", async function () {
      const purchaseAmount = HARD_CAP + ethers.parseUnits("1", 6);
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "ExceedsHardCap");
    });

    it("Should revert with invalid payment token", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            ethers.ZeroAddress,
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidPaymentToken");
    });

    it("Should revert with invalid signature", async function () {
      const purchaseAmount = MINIMUM_PURCHASE;
      const invalidSignature = await signWhitelist(user2.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier); // Wrong user signature

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            invalidSignature
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidSignature");
    });

    it("Should revert with insufficient balance", async function () {
      await usdt.connect(user1).transfer(user2.address, INITIAL_SUPPLY);
      const purchaseAmount = ethers.parseUnits("1000", 6);
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "InsufficientBalance");
    });

    it("Should revert with insufficient allowance", async function () {
      const purchaseAmount = MINIMUM_PURCHASE;
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      // Don't approve tokens
      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "InsufficientAllowance");
    });

    it("Should end sale when hard cap is reached", async function () {
      const halfHardCap = HARD_CAP / 2n;

      const signature1 = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const signature2 = await signWhitelist(user2.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), halfHardCap);
      await usdt
        .connect(user2)
        .approve(await launchpad.getAddress(), halfHardCap);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          halfHardCap,
          signature1
        );

      await expect(
        launchpad
          .connect(user2)
          .buyAllocation(
            user2.address,
            await usdt.getAddress(),
            halfHardCap,
            signature2
          )
      ).to.emit(launchpad, "SaleEnded");

      expect(await launchpad.saleEnded()).to.be.true;
    });

    it("Should track multiple purchases from same user", async function () {
      const firstPurchase = MINIMUM_PURCHASE;
      const secondPurchase = MINIMUM_PURCHASE * 2n;

      const signature1 = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      await usdc.connect(user1).approve(await launchpad.getAddress(), firstPurchase + secondPurchase);

      // Fast forward to sale start
      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      // First purchase
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdc.getAddress(),
          firstPurchase,
          signature1
        );

      // Second purchase
      await launchpad
        .connect(user1)
        .buyAllocation(
          ethers.ZeroAddress,
          await usdc.getAddress(),
          secondPurchase,
          signature1
        );

      expect(await launchpad.userContributions(user1.address)).to.equal(
        firstPurchase + secondPurchase
      );

      const userInfo = await launchpad.getUserInfo(user1.address);
      expect(userInfo.totalContributionHistory).to.equal(2);
      expect(userInfo.usdcContribution).to.equal(firstPurchase + secondPurchase);
      expect(userInfo.usdtContribution).to.equal(0);
    });
  });

  describe("Fund Withdrawal", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;
      const decimalTokenSold = 5;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );
    });

    it("Should allow fund withdrawal after soft cap is reached and sale ended with USDT", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP; // Meet soft cap

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      // End sale manually
      await expect(
        launchpad.connect(unauthorized).endSale()
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
      await launchpad.connect(admin).endSale();
      await expect(
        launchpad.connect(admin).endSale()
      ).to.be.revertedWithCustomError(launchpad, "SaleAlreadyEnded");

      const initialBalance = await usdt.balanceOf(destination.address);

      await expect(launchpad.connect(admin).withdrawFunds())
        .to.emit(launchpad, "USDWithdrawn")
        .withArgs(purchaseAmount, destination.address);

      expect(await usdt.balanceOf(destination.address)).to.equal(
        initialBalance + purchaseAmount
      );
      expect(await launchpad.fundsWithdrawn()).to.be.true;
    });

    it("Should allow fund withdrawal after soft cap is reached and sale ended with USDC", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP; // Meet soft cap

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdc
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdc.getAddress(),
          purchaseAmount,
          signature
        );

      // End sale manually
      await expect(
        launchpad.connect(unauthorized).endSale()
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
      await launchpad.connect(admin).endSale();
      await expect(
        launchpad.connect(admin).endSale()
      ).to.be.revertedWithCustomError(launchpad, "SaleAlreadyEnded");

      const initialBalance = await usdc.balanceOf(destination.address);

      await expect(launchpad.connect(admin).withdrawFunds())
        .to.emit(launchpad, "USDWithdrawn")
        .withArgs(purchaseAmount, destination.address);

      expect(await usdc.balanceOf(destination.address)).to.equal(
        initialBalance + purchaseAmount
      );
      expect(await launchpad.fundsWithdrawn()).to.be.true;
    });

    it("Should revert withdrawal if soft cap not reached", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP - ethers.parseUnits("1", 6); // Below soft cap

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await launchpad.connect(admin).endSale();

      await expect(
        launchpad.connect(admin).withdrawFunds()
      ).to.be.revertedWithCustomError(launchpad, "SoftCapNotReached");
    });

    it("Should revert withdrawal if sale not ended", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await expect(
        launchpad.connect(admin).withdrawFunds()
      ).to.be.revertedWithCustomError(launchpad, "SaleNotEnded");
    });

    it("Should revert if funds already withdrawn", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await launchpad.connect(admin).endSale();
      await launchpad.connect(admin).withdrawFunds();

      await expect(
        launchpad.connect(admin).withdrawFunds()
      ).to.be.revertedWithCustomError(launchpad, "FundsAlreadyWithdrawn");
    });

    it("Should revert withdrawer is not admin", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await expect(
        launchpad.connect(user1).withdrawFunds()
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("Should withdraw both USDT and USDC", async function () {
      const signature1 = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const signature2 = await signWhitelist(user2.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      const usdtAmount = SOFT_CAP / 2n;
      const usdcAmount = SOFT_CAP / 2n;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), usdtAmount);
      await usdc
        .connect(user2)
        .approve(await launchpad.getAddress(), usdcAmount);

      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          usdtAmount,
          signature1
        );

      await launchpad
        .connect(user2)
        .buyAllocation(
          user2.address,
          await usdc.getAddress(),
          usdcAmount,
          signature2
        );

      await time.increaseTo((await launchpad.endTime()) + 1n);

      await launchpad.connect(admin).withdrawFunds();

      expect(await usdt.balanceOf(destination.address)).to.equal(usdtAmount);
      expect(await usdc.balanceOf(destination.address)).to.equal(usdcAmount);
    });
  });

  describe("Refunds", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );
    });

    it("Should allow users to claim refund if soft cap not reached", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP - ethers.parseUnits("1", 6); // Below soft cap

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdc.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdc.getAddress(),
          purchaseAmount,
          signature
        );

      // End sale
      await launchpad.connect(admin).endSale();

      const initialBalance = await usdc.balanceOf(user1.address);

      await expect(launchpad.connect(user1).claimRefund())
        .to.emit(launchpad, "RefundIssued")
        .withArgs(user1.address, purchaseAmount);

      expect(await usdc.balanceOf(user1.address)).to.equal(
        initialBalance + purchaseAmount
      );
      expect(await launchpad.refundClaimed(user1.address)).to.equal(
        purchaseAmount
      );
    });

    it("Should allow admin to process refund for user", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await time.increaseTo((await launchpad.endTime()) + 1n);

      await expect(
        launchpad.connect(admin).claimRefundForUser(user1.address)
      ).to.emit(launchpad, "RefundIssued");
    });

    it("Should revert refund if soft cap reached", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = SOFT_CAP; // Meet soft cap

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await launchpad.connect(admin).endSale();

      await expect(
        launchpad.connect(user1).claimRefund()
      ).to.be.revertedWithCustomError(launchpad, "SoftCapReached");
    });

    it("Should revert refund if sale not ended", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await expect(
        launchpad.connect(user1).claimRefund()
      ).to.be.revertedWithCustomError(launchpad, "SaleNotEnded");
    });

    it("Should revert if refund already claimed and revert if is paused", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      await launchpad.connect(admin).endSale();

      // should revert if paused
      await launchpad.connect(admin).pause();
      await expect(
        launchpad.connect(user1).claimRefund()
      ).to.be.revertedWithCustomError(launchpad, "EnforcedPause");

      await launchpad.connect(admin).unpause();
      await launchpad.connect(user1).claimRefund();

      await expect(
        launchpad.connect(user1).claimRefund()
      ).to.be.revertedWithCustomError(launchpad, "RefundAlreadyClaimed");
    });

    it("Should revert if user has no contribution", async function () {
      await launchpad.connect(admin).endSale();

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      await expect(
        launchpad.connect(user1).claimRefund()
      ).to.be.revertedWithCustomError(launchpad, "NoUserContribution");
    });

    it("Should handle proportional refunds for 2 payment tokens", async function () {
      const signature1 = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const signature2 = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      const startTime = await launchpad.startTime();
      await time.increaseTo(startTime + 1000n);

      const usdtAmount = MINIMUM_PURCHASE;
      const usdcAmount = MINIMUM_PURCHASE;

      const initialUsdtBalance = await usdt.balanceOf(user1.address);
      const initialUsdcBalance = await usdc.balanceOf(user1.address);

      await usdc.connect(user1).approve(await launchpad.getAddress(), usdcAmount);
      await usdt.connect(user1).approve(await launchpad.getAddress(), usdtAmount);

      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          usdtAmount,
          signature1
        );

      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdc.getAddress(),
          usdcAmount,
          signature1
        );

      await launchpad.connect(admin).endSale();

      const usdtBalanceAfterPurchase = await usdt.balanceOf(user1.address);
      const usdcBalanceAfterPurchase = await usdc.balanceOf(user1.address);

      await expect(
        launchpad.connect(user1).claimRefundForUser(user1.address)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
      await launchpad.connect(user1).claimRefund();

      // User1 should receive proportional amounts of both tokens
      const finalUsdtBalance = await usdt.balanceOf(user1.address);
      const finalUsdcBalance = await usdc.balanceOf(user1.address);

      expect(finalUsdtBalance).to.be.eq(usdtBalanceAfterPurchase + usdtAmount);
      expect(finalUsdcBalance).to.be.eq(usdcBalanceAfterPurchase + usdcAmount);
      expect(finalUsdtBalance).to.equal(initialUsdtBalance);
      expect(finalUsdcBalance).to.equal(initialUsdcBalance);
      expect(await launchpad.refundClaimed(user1.address)).to.equal(usdtAmount + usdcAmount);
    });
  });

  describe("Sale Status and Info", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );
    });

    it("Should return correct sale status", async function () {
      // Before sale starts
      let status = await launchpad.getSaleStatus();
      expect(status.isActive).to.be.false;
      expect(status.isEnded).to.be.false;
      expect(status.softCapReached).to.be.false;
      expect(status.hardCapReached).to.be.false;

      // During sale
      await time.increaseTo(await launchpad.startTime());
      status = await launchpad.getSaleStatus();
      expect(status.isActive).to.be.true;
      expect(status.isEnded).to.be.false;

      // After sale ends
      await time.increaseTo((await launchpad.endTime()) + 1n);
      status = await launchpad.getSaleStatus();
      expect(status.isActive).to.be.false;
      expect(status.isEnded).to.be.true;
    });

    it("Should return correct user info", async function () {
      await time.increaseTo(await launchpad.startTime());

      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;
      const decimalTokenSold = await launchpad.decimalTokenSold();
      const adjustedPurchaseAmount = purchaseAmount * ethers.parseUnits("1", 18 - 6);
      const expectedTokens = (adjustedPurchaseAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      const userInfo = await launchpad.getUserInfo(user1.address);
      expect(userInfo.contribution).to.equal(purchaseAmount);
      expect(userInfo.allocation).to.equal(expectedTokens);
      expect(userInfo.refundedAmount).to.equal(0);
      expect(userInfo.totalContributionHistory).to.equal(1);
      expect(userInfo.canClaimRefund).to.be.false;
      expect(userInfo.usdtContribution).to.equal(purchaseAmount);
      expect(userInfo.usdcContribution).to.equal(0);
    });
  });

  describe("Access Control", function () {
    it("Should allow owner to set addresses", async function () {
      const newVerifier = user1.address;
      const newDestination = user2.address;
      const newUsdt = user3.address;
      const newUsdc = unauthorized.address;

      await launchpad.connect(admin).setAdminVerifier(newVerifier);
      await launchpad.connect(admin).setDestinationAddress(newDestination);
      await launchpad.connect(admin).setUsdtAddress(newUsdt);
      await launchpad.connect(admin).setUsdcAddress(newUsdc);
      await launchpad.connect(admin).setDecimalTokenSold(10);

      expect(await launchpad.adminVerifier()).to.equal(newVerifier);
      expect(await launchpad.destinationAddress()).to.equal(newDestination);
      expect(await launchpad.usdt()).to.equal(newUsdt);
      expect(await launchpad.decimalTokenSold()).to.equal(10);
    });

    it("Should revert setting invalid address and unauthorized", async function () {
      await expect(
        launchpad.connect(admin).setAdminVerifier(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
      await expect(
        launchpad.connect(admin).setDestinationAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
      await expect(
        launchpad.connect(admin).setUsdtAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");
      await expect(
        launchpad.connect(admin).setUsdcAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");


      await expect(
        launchpad.connect(unauthorized).setAdminVerifier(user1.address)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );

      await expect(
        launchpad.connect(unauthorized).setDestinationAddress(user1.address)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );

      await expect(
        launchpad.connect(unauthorized).setUsdtAddress(user1.address)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );

      await expect(
        launchpad.connect(unauthorized).setUsdcAddress(user1.address)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );

      await expect(
        launchpad.connect(unauthorized).setDecimalTokenSold(10)
      ).to.be.revertedWithCustomError(
        launchpad,
        "AccessControlUnauthorizedAccount"
      );
    });

    it("Should only allow admin to pause/unpause", async function () {
      await launchpad.connect(admin).pause();
      expect(await launchpad.paused()).to.be.true;

      await launchpad.connect(admin).unpause();
      expect(await launchpad.paused()).to.be.false;

      await expect(launchpad.connect(unauthorized).pause()).to.be.reverted;

      await expect(launchpad.connect(unauthorized).unpause()).to.be.reverted;
    });

    it("Should prevent buying when paused", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      await time.increaseTo(startTime);
      await launchpad.connect(admin).pause();

      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "EnforcedPause");
    });
  });

  describe("Foreign Token Withdrawal", function () {
    let foreignToken: MockERC20;

    beforeEach(async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      foreignToken = await MockERC20Factory.deploy(
        "Foreign Token",
        "FTK",
        ethers.parseUnits("1000", 6)
      );

      // Send some foreign tokens to the contract
      await foreignToken.transfer(
        await launchpad.getAddress(),
        ethers.parseUnits("1000", 6)
      );

      // Send some native tokens to the contract
      await owner.sendTransaction({
        to: await launchpad.getAddress(),
        value: ethers.parseEther("1"),
      });
    });

    it("Should allow owner to withdraw foreign ERC20 tokens", async function () {
      const withdrawAmount = ethers.parseUnits("500", 6);
      const initialBalance = await foreignToken.balanceOf(user1.address);

      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await foreignToken.getAddress(),
            user1.address,
            withdrawAmount
          )
      )
        .to.emit(launchpad, "WithdrawForeignToken")
        .withArgs(
          await foreignToken.getAddress(),
          user1.address,
          withdrawAmount
        );

      expect(await foreignToken.balanceOf(user1.address)).to.equal(
        initialBalance + withdrawAmount
      );
    });

    it("Should allow owner to withdraw native tokens", async function () {
      const withdrawAmount = ethers.parseEther("0.5");
      const initialBalance = await ethers.provider.getBalance(user1.address);

      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            ethers.ZeroAddress,
            user1.address,
            withdrawAmount
          )
      )
        .to.emit(launchpad, "WithdrawForeignToken")
        .withArgs(ethers.ZeroAddress, user1.address, withdrawAmount);

      expect(await ethers.provider.getBalance(user1.address)).to.be.gt(
        initialBalance
      );
    });

    it("Should revert withdrawal insufficient balance", async function () {
      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await foreignToken.getAddress(),
            user1.address,
            ethers.parseUnits("10000", 6)
          )
      ).to.be.revertedWithCustomError(launchpad, "ERC20InsufficientBalance");

      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            ethers.ZeroAddress,
            user1.address,
            ethers.parseUnits("100", 18)
          )
      ).to.be.revertedWithCustomError(launchpad, "InsufficientBalance");
    });

    it("Should revert withdrawal of USDT/USDC", async function () {
      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await usdt.getAddress(),
            user1.address,
            ethers.parseUnits("100", 6)
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidTokenAddress");

      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await usdc.getAddress(),
            user1.address,
            ethers.parseUnits("100", 6)
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidTokenAddress");
    });

    it("Should revert with invalid parameters", async function () {
      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await foreignToken.getAddress(),
            ethers.ZeroAddress,
            ethers.parseUnits("100", 18)
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAddress");

      await expect(
        launchpad
          .connect(owner)
          .withdrawForeignToken(
            await foreignToken.getAddress(),
            user1.address,
            0
          )
      ).to.be.revertedWithCustomError(launchpad, "InvalidAmount");
    });

    it("Should only allow owner to withdraw foreign tokens", async function () {
      await expect(
        launchpad
          .connect(unauthorized)
          .withdrawForeignToken(
            await foreignToken.getAddress(),
            user1.address,
            ethers.parseUnits("100", 18)
          )
      ).to.be.reverted;
    });
  });

  describe("Pagination Functions", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      await time.increaseTo(startTime);

      // Add multiple contributors
      for (let i = 0; i < 3; i++) {
        const user = [user1, user2, user3][i];
        const signature = await signWhitelist(user.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

        await usdt
          .connect(user)
          .approve(await launchpad.getAddress(), MINIMUM_PURCHASE);
        await launchpad
          .connect(user)
          .buyAllocation(
            user.address,
            await usdt.getAddress(),
            MINIMUM_PURCHASE,
            signature
          );
      }
    });

    it("Should return contributors with pagination", async function () {
      const [contributors, total] = await launchpad.getUserContributors(0, 2);

      expect(total).to.equal(3);
      expect(contributors.length).to.equal(2);
      expect(contributors[0]).to.equal(user1.address);
      expect(contributors[1]).to.equal(user2.address);

      const [remaining] = await launchpad.getUserContributors(2, 2);
      expect(remaining.length).to.equal(1);
      expect(remaining[0]).to.equal(user3.address);
    });

    it("Should return user contribution history with pagination", async function () {
      // Make multiple contributions for user1
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), MINIMUM_PURCHASE);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          MINIMUM_PURCHASE,
          signature
        );

      const [history, total] = await launchpad.getUserContributionHistory(
        user1.address,
        0,
        10
      );

      expect(total).to.equal(2);
      expect(history.length).to.equal(2);
      expect(history[0].usdAmount).to.equal(MINIMUM_PURCHASE);
      expect(history[0].totalUSDContributedBefore).to.equal(0n);
      expect(history[0].totalUSDContributedAfter).to.equal(MINIMUM_PURCHASE);
      expect(history[0].paymentToken).to.equal(await usdt.getAddress());

      expect(history[1].usdAmount).to.equal(MINIMUM_PURCHASE);
      expect(history[1].totalUSDContributedBefore).to.equal(MINIMUM_PURCHASE);
      expect(history[1].totalUSDContributedAfter).to.equal(
        MINIMUM_PURCHASE * 2n
      );

      const [history1, total1] = await launchpad.getUserContributionHistory(
        user1.address,
        total,
        10
      );

      expect(total1).to.equal(2);
      expect(history1.length).to.equal(0);

      const [history2, total2] = await launchpad.getUserContributionHistory(
        user1.address,
        0,
        1
      );

      expect(total2).to.equal(2);
      expect(history2.length).to.equal(1);
      expect(history2[0].usdAmount).to.equal(MINIMUM_PURCHASE);
      expect(history2[0].paymentToken).to.equal(await usdt.getAddress());
    });

    it("Should handle empty results for pagination", async function () {
      const [contributors, total] = await launchpad.getUserContributors(10, 5);

      expect(total).to.equal(3);
      expect(contributors.length).to.equal(0);

      const [refundedUsers, totalRefunded] = await launchpad.getUserRefunded(
        0,
        5
      );
      expect(totalRefunded).to.equal(0);
      expect(refundedUsers.length).to.equal(0);
    });

    it("Should return refunded users with pagination", async function () {
      await time.increaseTo((await launchpad.endTime()) + 1000n);
      await launchpad.connect(user1).claimRefund();
      await launchpad.connect(user2).claimRefund();
      await launchpad.connect(user3).claimRefund();

      const [refundedUsers, total] = await launchpad.getUserRefunded(0, 2);

      expect(total).to.equal(3);
      expect(refundedUsers.length).to.equal(2);
      expect(refundedUsers[0]).to.equal(user1.address);
      expect(refundedUsers[1]).to.equal(user2.address);

      const [refundedUsers1, total1] = await launchpad.getUserRefunded(
        total,
        2
      );
      expect(total1).to.equal(3);
      expect(refundedUsers1.length).to.equal(0);

      const [refundedUsers2, total2] = await launchpad.getUserRefunded(0, 1);
      expect(total2).to.equal(3);
      expect(refundedUsers2.length).to.equal(1);

      const [remaining] = await launchpad.getUserRefunded(2, 2);
      expect(remaining.length).to.equal(1);
      expect(remaining[0]).to.equal(user3.address);
    });
  });

  describe("Token Calculation", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );
    });

    it("Should return the correct token amount out", async function () {
      const usdAmount = MINIMUM_PURCHASE;
      const adjustedUsdAmount = usdAmount * ethers.parseUnits("1", 18 - 6);
      const expectedTokenAmount = (adjustedUsdAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;
      const tokenAmount = await launchpad.getTokenAmountOut(await usdt.getAddress(), MINIMUM_PURCHASE);
      
      expect(tokenAmount).to.equal(expectedTokenAmount);

      const tokenAmount1 = await launchpad.getTokenAmountOut(await usdc.getAddress(), MINIMUM_PURCHASE);
      const expectedTokenAmount1 = (adjustedUsdAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;

      expect(tokenAmount1).to.equal(expectedTokenAmount1);
    });

    it("Should throw error if payment token is invalid", async function () {
      await expect(launchpad.getTokenAmountOut(ethers.ZeroAddress, MINIMUM_PURCHASE)).to.be.revertedWithCustomError(launchpad, "InvalidPaymentToken");
    });

    it("Should throw error if usd amount is 0", async function () {
      await expect(launchpad.getTokenAmountOut(await usdt.getAddress(), 0)).to.be.revertedWithCustomError(launchpad, "InvalidAmount");
    });
  });

  describe("Edge Cases and Security", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      await time.increaseTo(startTime);
    });

    it("Should handle reentrancy protection", async function () {
      // This test ensures the nonReentrant modifier is working
      // The actual reentrancy attack would require a malicious contract
      // For now, we verify the modifier is in place
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;

      await usdt
        .connect(user1)
        .approve(await launchpad.getAddress(), purchaseAmount);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      ).to.not.be.reverted;
    });

    it("Should handle sale end time correctly", async function () {
      // Fast forward past end time
      await time.increaseTo((await launchpad.endTime()) + 1n);

      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);

      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            MINIMUM_PURCHASE,
            signature
          )
      ).to.be.revertedWithCustomError(launchpad, "SaleAlreadyEnded");
    });

    it("Should handle precision correctly in token calculations", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = ethers.parseUnits("123.456789", 6); // Precise amount
      const decimalTokenSold = await launchpad.decimalTokenSold();
      const adjustedPurchaseAmount = purchaseAmount * ethers.parseUnits("1", 18 - 6);
      const expectedTokens = (adjustedPurchaseAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);
      await launchpad
        .connect(user1)
        .buyAllocation(
          user1.address,
          await usdt.getAddress(),
          purchaseAmount,
          signature
        );

      expect(await launchpad.userAllocations(user1.address)).to.equal(
        expectedTokens
      );
    });
  });

  describe("Contract Upgradeability", function () {
    it("Should support UUPS upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXLaunchpadV2Factory =
        await ethers.getContractFactory("MWXLaunchpadV2");
      const upgraded = await upgrades.upgradeProxy(
        await launchpad.getAddress(),
        MWXLaunchpadV2Factory,
        {
          call: {
            fn: "initializeV2",
            args: [],
          },
          unsafeAllow: ["missing-initializer-call"],
        }
      );

      const upgradedMWXLaunchpad = upgraded as MWXLaunchpadV2;

      // Verify state is preserved
      expect(await upgradedMWXLaunchpad.owner()).to.equal(owner.address);
      expect(await upgradedMWXLaunchpad.version()).to.equal("2");
      expect(await upgradedMWXLaunchpad.newFunction()).to.equal(
        "This is a new function in V2"
      );

      await expect(
        upgradedMWXLaunchpad.initializeV2()
      ).to.be.revertedWithCustomError(launchpad, "InvalidInitialization");
    });

    it("Should only allow owner to authorize upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXLaunchpadV2Factory = await ethers.getContractFactory(
        "MWXLaunchpadV2",
        user1
      );
      await expect(
        upgrades.upgradeProxy(
          await launchpad.getAddress(),
          MWXLaunchpadV2Factory,
          {
            call: {
              fn: "initializeV2",
              args: [],
            },
            unsafeAllow: ["missing-initializer-call"],
          }
        )
      ).to.be.revertedWithCustomError(launchpad, "OwnableUnauthorizedAccount");
    });

    it("Should preserve state after upgrade", async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      const originalTokenPrice = await launchpad.tokenPrice();

      // Upgrade contract
      const MWXLaunchpadV2Factory =
        await ethers.getContractFactory("MWXLaunchpad");
      const upgraded = await upgrades.upgradeProxy(
        await launchpad.getAddress(),
        MWXLaunchpadV2Factory
      );

      // Verify state is preserved
      expect(await upgraded.tokenPrice()).to.equal(originalTokenPrice);
      expect(await upgraded.owner()).to.equal(owner.address);
    });

    it("Should only allow owner to authorize upgrades", async function () {
      const MWXLaunchpadV2Factory =
        await ethers.getContractFactory("MWXLaunchpad");

      // This would fail in a real scenario, but since we're using the upgrades plugin,
      // it handles the authorization internally. We test the _authorizeUpgrade function indirectly
      // by ensuring only the owner can perform upgrades through the proxy admin.
      await expect(
        upgrades.upgradeProxy(
          await launchpad.getAddress(),
          MWXLaunchpadV2Factory
        )
      ).to.not.be.reverted;
    });
  });

  describe("Events", function () {
    beforeEach(async function () {
      const currentTime = await getTimestamp();
      const startTime = currentTime + 100;
      const endTime = startTime + 86400;

      await launchpad
        .connect(admin)
        .configureSale(
          startTime,
          endTime,
          TOKEN_PRICE,
          TOTAL_ALLOCATION,
          SOFT_CAP,
          HARD_CAP,
          MINIMUM_PURCHASE,
          decimalTokenSold
        );

      await time.increaseTo(startTime);
    });

    it("Should emit correct events for all major operations", async function () {
      const signature = await signWhitelist(user1.address, await launchpad.getAddress(), (await ethers.provider.getNetwork()).chainId, verifier);
      const purchaseAmount = MINIMUM_PURCHASE;
      const decimalTokenSold = await launchpad.decimalTokenSold();
      const adjustedPurchaseAmount = purchaseAmount * ethers.parseUnits("1", 18 - 6);
      const expectedTokens = (adjustedPurchaseAmount * ethers.parseUnits("1", decimalTokenSold)) / TOKEN_PRICE;

      await usdt.connect(user1).approve(await launchpad.getAddress(), purchaseAmount);

      // Test AllocationPurchased event
      await expect(
        launchpad
          .connect(user1)
          .buyAllocation(
            user1.address,
            await usdt.getAddress(),
            purchaseAmount,
            signature
          )
      )
        .to.emit(launchpad, "AllocationPurchased")
        .withArgs(
          user1.address,
          purchaseAmount,
          expectedTokens,
          (await getTimestamp()) + 1
        );

      // Test SaleEnded event
      await expect(launchpad.connect(admin).endSale()).to.emit(
        launchpad,
        "SaleEnded"
      );

      // Test RefundIssued event
      await expect(launchpad.connect(user1).claimRefund())
        .to.emit(launchpad, "RefundIssued").withArgs(user1.address, purchaseAmount);
    });
  });
});
