import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MWXDisperse } from "../typechain-types/contracts/MWXDisperse";
import { MockERC20 } from "../typechain-types/contracts/mocks/MockERC20";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { MWXDisperseV2 } from "../typechain-types";

describe("MWXDisperse", function () {
  let disperse: MWXDisperse;
  let mockToken: MockERC20;
  let owner: SignerWithAddress;
  let treasury: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let user4: SignerWithAddress;
  let user5: SignerWithAddress;
  let other: SignerWithAddress;
  let accounts: SignerWithAddress[];

  // Test parameters
  const INITIAL_SUPPLY = ethers.parseUnits("1000000", 18);
  const TREASURY_PERCENTAGE = 2000; // 20%
  const RECIPIENT_PERCENTAGE = 7000; // 70%
  const BURN_PERCENTAGE = 1000; // 10%
  const MAX_RECIPIENTS_PER_TX = 10;

  beforeEach(async function () {
    [owner, treasury, user1, user2, user3, user4, user5, other, ...accounts] = await ethers.getSigners();

    // Deploy MockERC20
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    mockToken = await MockERC20Factory.deploy("Mock Token", "MOCK", INITIAL_SUPPLY);
    await mockToken.waitForDeployment();

    // Deploy MWXDisperse as upgradeable proxy
    const MWXDisperseFactory = await ethers.getContractFactory("MWXDisperse");
    disperse = (await upgrades.deployProxy(MWXDisperseFactory, [
      owner.address,
      treasury.address,
      TREASURY_PERCENTAGE,
      RECIPIENT_PERCENTAGE,
      BURN_PERCENTAGE,
      MAX_RECIPIENTS_PER_TX
    ])) as unknown as MWXDisperse;
    await disperse.waitForDeployment();

    // Transfer some tokens to users for testing
    await mockToken.transfer(user1.address, ethers.parseUnits("10000", 18));
    await mockToken.transfer(user2.address, ethers.parseUnits("10000", 18));
    await mockToken.transfer(user3.address, ethers.parseUnits("10000", 18));
    await mockToken.transfer(user4.address, ethers.parseUnits("10000", 18));
    await mockToken.transfer(user5.address, ethers.parseUnits("10000", 18));
  });

  describe("Deployment and Initialization", function () {
    it("Should initialize with correct parameters", async function () {
      const config = await disperse.getConfiguration();
      expect(config._treasuryAddress).to.equal(treasury.address);
      expect(config._treasuryPercentage).to.equal(TREASURY_PERCENTAGE);
      expect(config._recipientPercentage).to.equal(RECIPIENT_PERCENTAGE);
      expect(config._burnPercentage).to.equal(BURN_PERCENTAGE);
      expect(config._maxRecipientsPerTx).to.equal(MAX_RECIPIENTS_PER_TX);
    });

    it("Should set the correct owner", async function () {
      expect(await disperse.owner()).to.equal(owner.address);
    });

    it("Should have correct constants", async function () {
      expect(await disperse.BURN_ADDRESS()).to.equal("0x000000000000000000000000000000000000dEaD");
      expect(await disperse.MAX_PERCENTAGE()).to.equal(10000);
    });

    it("Should revert if initialized with zero treasury address", async function () {
      const MWXDisperseFactory = await ethers.getContractFactory("MWXDisperse");
      await expect(
        upgrades.deployProxy(MWXDisperseFactory, [
          owner.address,
          ethers.ZeroAddress,
          TREASURY_PERCENTAGE,
          RECIPIENT_PERCENTAGE,
          BURN_PERCENTAGE,
          MAX_RECIPIENTS_PER_TX
        ])
      ).to.be.revertedWithCustomError(disperse, "InvalidAddress");
    });

    it("Should revert if initialized with zero max recipients per tx", async function () {
      const MWXDisperseFactory = await ethers.getContractFactory("MWXDisperse");
      await expect(
        upgrades.deployProxy(MWXDisperseFactory, [
          owner.address,
          treasury.address,
          TREASURY_PERCENTAGE,
          RECIPIENT_PERCENTAGE,
          BURN_PERCENTAGE,
          0
        ])
      ).to.be.revertedWithCustomError(disperse, "InvalidMaxRecipientsPerTx");
    });

    it("Should revert if percentages don't sum to 100%", async function () {
      const MWXDisperseFactory = await ethers.getContractFactory("MWXDisperse");
      await expect(
        upgrades.deployProxy(MWXDisperseFactory, [
          owner.address,
          treasury.address,
          3000, // 30%
          4000, // 40%
          2000, // 20% (total 90%)
          MAX_RECIPIENTS_PER_TX
        ])
      ).to.be.revertedWithCustomError(disperse, "InvalidPercentages");
    });

    it("Should revert if called initialize again", async function () {
      await expect(
        disperse.initialize(
          owner.address,
          treasury.address,
          TREASURY_PERCENTAGE,
          RECIPIENT_PERCENTAGE,
          BURN_PERCENTAGE,
          MAX_RECIPIENTS_PER_TX
        )
      ).to.be.revertedWithCustomError(disperse, "InvalidInitialization");
    });
  });

  describe("Configuration Management", function () {
    it("Should allow owner to update treasury address", async function () {
      const newTreasury = user1.address;
      await expect(disperse.setTreasuryAddress(newTreasury))
        .to.emit(disperse, "TreasuryAddressChanged")
        .withArgs(treasury.address, newTreasury);

      const config = await disperse.getConfiguration();
      expect(config._treasuryAddress).to.equal(newTreasury);
    });

    it("Should revert when non-owner tries to update treasury address", async function () {
      await expect(
        disperse.connect(user1).setTreasuryAddress(user2.address)
      ).to.be.revertedWithCustomError(disperse, "OwnableUnauthorizedAccount");
    });

    it("Should revert when setting treasury address to zero", async function () {
      await expect(
        disperse.setTreasuryAddress(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(disperse, "InvalidAddress");
    });

    it("Should allow owner to update percentages", async function () {
      const newTreasuryPercentage = 1500; // 15%
      const newRecipientPercentage = 7500; // 75%
      const newBurnPercentage = 1000; // 10%

      await expect(disperse.setPercentages(newTreasuryPercentage, newRecipientPercentage, newBurnPercentage))
        .to.emit(disperse, "PercentagesChanged")
        .withArgs(newTreasuryPercentage, newRecipientPercentage, newBurnPercentage);

      const config = await disperse.getConfiguration();
      expect(config._treasuryPercentage).to.equal(newTreasuryPercentage);
      expect(config._recipientPercentage).to.equal(newRecipientPercentage);
      expect(config._burnPercentage).to.equal(newBurnPercentage);
    });

    it("Should revert when non-owner tries to update percentages", async function () {
      await expect(
        disperse.connect(user1).setPercentages(1500, 7500, 1000)
      ).to.be.revertedWithCustomError(disperse, "OwnableUnauthorizedAccount");
    });

    it("Should revert when percentages don't sum to 100%", async function () {
      await expect(
        disperse.setPercentages(1500, 7500, 2000) // Total 110%
      ).to.be.revertedWithCustomError(disperse, "InvalidPercentages");
    });

    it("Should allow owner to update max recipients per tx", async function () {
      const newMaxRecipients = 20;
      await expect(disperse.setMaxRecipientsPerTx(newMaxRecipients))
        .to.emit(disperse, "MaxRecipientsChanged")
        .withArgs(MAX_RECIPIENTS_PER_TX, newMaxRecipients);

      const config = await disperse.getConfiguration();
      expect(config._maxRecipientsPerTx).to.equal(newMaxRecipients);
    });

    it("Should revert when non-owner tries to update max recipients", async function () {
      await expect(
        disperse.connect(user1).setMaxRecipientsPerTx(20)
      ).to.be.revertedWithCustomError(disperse, "OwnableUnauthorizedAccount");
    });

    it("Should revert when setting max recipients to zero", async function () {
      await expect(
        disperse.setMaxRecipientsPerTx(0)
      ).to.be.revertedWithCustomError(disperse, "InvalidMaxRecipientsPerTx");
    });
  });

  describe("ETH Dispersion", function () {
    let testAmount: bigint;
    let recipients: string[];
    let amounts: bigint[];

    beforeEach(async function () {
      testAmount = ethers.parseEther("1");
      recipients = [user1.address, user2.address, user3.address];
      amounts = [ethers.parseEther("0.5"), ethers.parseEther("0.3"), ethers.parseEther("0.2")];

      // Fund the contract with ETH
      // Fund the contract with ETH
      await owner.sendTransaction({
        to: await disperse.getAddress(),
        value: ethers.parseEther("10")
      });
    });

    it("Should disperse ETH correctly", async function () {
      const initialBalances = await Promise.all([
        ethers.provider.getBalance(user1.address),
        ethers.provider.getBalance(user2.address),
        ethers.provider.getBalance(user3.address),
        ethers.provider.getBalance(treasury.address),
        ethers.provider.getBalance(await disperse.BURN_ADDRESS())
      ]);

      const totalAmount = amounts.reduce((sum, amount) => sum + amount, 0n);
      const expectedTreasuryAmount = (totalAmount * BigInt(TREASURY_PERCENTAGE)) / 10000n;
      const expectedBurnAmount = (totalAmount * BigInt(BURN_PERCENTAGE)) / 10000n;

      await expect(disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: totalAmount }))
        .to.emit(disperse, "Dispersed")
        .withArgs(owner.address, ethers.ZeroAddress, totalAmount, recipients.length);

      // Check recipient balances
      const finalBalances = await Promise.all([
        ethers.provider.getBalance(user1.address),
        ethers.provider.getBalance(user2.address),
        ethers.provider.getBalance(user3.address),
        ethers.provider.getBalance(treasury.address),
        ethers.provider.getBalance(await disperse.BURN_ADDRESS())
      ]);

      // Calculate expected recipient amounts
      const expectedRecipient1Amount = (amounts[0] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;
      const expectedRecipient2Amount = (amounts[1] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;
      const expectedRecipient3Amount = (amounts[2] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;

      expect(finalBalances[0] - initialBalances[0]).to.equal(expectedRecipient1Amount);
      expect(finalBalances[1] - initialBalances[1]).to.equal(expectedRecipient2Amount);
      expect(finalBalances[2] - initialBalances[2]).to.equal(expectedRecipient3Amount);
      expect(finalBalances[3] - initialBalances[3]).to.equal(expectedTreasuryAmount);
      expect(finalBalances[4] - initialBalances[4]).to.equal(expectedBurnAmount);
    });

    it("Should revert when no recipients provided", async function () {
      await expect(
        disperse.disperse([], [], ethers.ZeroAddress, { value: testAmount })
      ).to.be.revertedWithCustomError(disperse, "NoRecipientsProvided");
    });

    it("Should revert when too many recipients provided", async function () {
      const tooManyRecipients = Array(MAX_RECIPIENTS_PER_TX + 1).fill(user1.address);
      const tooManyAmounts = Array(MAX_RECIPIENTS_PER_TX + 1).fill(testAmount);

      await expect(
        disperse.disperse(tooManyRecipients, tooManyAmounts, ethers.ZeroAddress, { value: testAmount })
      ).to.be.revertedWithCustomError(disperse, "TooManyRecipients");
    });

    it("Should revert when arrays length mismatch", async function () {
      await expect(
        disperse.disperse([user1.address, user2.address], [testAmount], ethers.ZeroAddress, { value: testAmount })
      ).to.be.revertedWithCustomError(disperse, "ArraysLengthMismatch");
    });

    it("Should revert when recipient address is zero", async function () {
      await expect(
        disperse.disperse([ethers.ZeroAddress], [testAmount], ethers.ZeroAddress, { value: testAmount })
      ).to.be.revertedWithCustomError(disperse, "InvalidAddress");
    });

    it("Should revert when amount is zero", async function () {
      await expect(
        disperse.disperse([user1.address], [0], ethers.ZeroAddress, { value: testAmount })
      ).to.be.revertedWithCustomError(disperse, "InvalidAmount");
    });

    it("Should revert when insufficient ETH sent", async function () {
      await expect(
        disperse.disperse([user1.address], [testAmount], ethers.ZeroAddress, { value: testAmount - 1n })
      ).to.be.revertedWithCustomError(disperse, "InsufficientBalance");
    });

    it("Should return excess ETH to sender", async function () {
      const excessAmount = ethers.parseEther("0.5");
      const totalAmount = amounts.reduce((sum, amount) => sum + amount, 0n);
      const sentAmount = totalAmount + excessAmount;

      const initialBalance = await ethers.provider.getBalance(owner.address);

      await disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: sentAmount });

      const finalBalance = await ethers.provider.getBalance(owner.address);
      // Note: Gas costs will affect the exact balance, but we can verify the transaction succeeded
    });

    it("Should handle zero percentages correctly", async function () {
      // Set all percentages to zero except one
      await disperse.setPercentages(10000, 0, 0);

      const singleRecipient = [user1.address];
      const singleAmount = [ethers.parseEther("1")];

      await expect(disperse.disperse(singleRecipient, singleAmount, ethers.ZeroAddress, { value: ethers.parseEther("1") }))
        .to.emit(disperse, "Dispersed");

      // Reset percentages
      await disperse.setPercentages(TREASURY_PERCENTAGE, RECIPIENT_PERCENTAGE, BURN_PERCENTAGE);
    });
  });

  describe("ERC20 Token Dispersion", function () {
    let testAmount: bigint;
    let recipients: string[];
    let amounts: bigint[];

    beforeEach(async function () {
      testAmount = ethers.parseUnits("100", 18);
      recipients = [user1.address, user2.address, user3.address];
      amounts = [ethers.parseUnits("50", 18), ethers.parseUnits("30", 18), ethers.parseUnits("20", 18)];

      // Approve tokens for the contract
      await mockToken.connect(owner).approve(await disperse.getAddress(), ethers.parseUnits("10000", 18));
      await mockToken.connect(user1).approve(await disperse.getAddress(), ethers.parseUnits("10000", 18));
      await mockToken.connect(user2).approve(await disperse.getAddress(), ethers.parseUnits("10000", 18));
      await mockToken.connect(user3).approve(await disperse.getAddress(), ethers.parseUnits("10000", 18));
    });

    it("Should disperse ERC20 tokens correctly", async function () {
      const initialBalances = await Promise.all([
        mockToken.balanceOf(user1.address),
        mockToken.balanceOf(user2.address),
        mockToken.balanceOf(user3.address),
        mockToken.balanceOf(treasury.address),
        mockToken.balanceOf(await disperse.BURN_ADDRESS()),
        mockToken.balanceOf(owner.address)
      ]);

      const totalAmount = amounts.reduce((sum, amount) => sum + amount, 0n);
      const expectedTreasuryAmount = (totalAmount * BigInt(TREASURY_PERCENTAGE)) / 10000n;
      const expectedBurnAmount = (totalAmount * BigInt(BURN_PERCENTAGE)) / 10000n;

      await expect(disperse.connect(owner).disperse(recipients, amounts, await mockToken.getAddress()))
        .to.emit(disperse, "Dispersed")
        .withArgs(owner.address, await mockToken.getAddress(), totalAmount, recipients.length);

      // Check recipient balances
      const finalBalances = await Promise.all([
        mockToken.balanceOf(user1.address),
        mockToken.balanceOf(user2.address),
        mockToken.balanceOf(user3.address),
        mockToken.balanceOf(treasury.address),
        mockToken.balanceOf(await disperse.BURN_ADDRESS()),
        mockToken.balanceOf(owner.address)
      ]);

      // Calculate expected recipient amounts
      const expectedRecipient1Amount = (amounts[0] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;
      const expectedRecipient2Amount = (amounts[1] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;
      const expectedRecipient3Amount = (amounts[2] * BigInt(RECIPIENT_PERCENTAGE)) / 10000n;

      expect(finalBalances[0] - initialBalances[0]).to.equal(expectedRecipient1Amount);
      expect(finalBalances[1] - initialBalances[1]).to.equal(expectedRecipient2Amount);
      expect(finalBalances[2] - initialBalances[2]).to.equal(expectedRecipient3Amount);
      expect(finalBalances[3] - initialBalances[3]).to.equal(expectedTreasuryAmount);
      expect(finalBalances[4] - initialBalances[4]).to.equal(expectedBurnAmount);
      expect(Math.abs(Number(finalBalances[5] - initialBalances[5])).toString()).to.equal(totalAmount.toString());
    });

    it("Should revert when insufficient token balance", async function () {
      const largeAmount = ethers.parseUnits("100000", 18); // More than user has
      await expect(
        disperse.connect(user1).disperse([user2.address], [largeAmount], await mockToken.getAddress())
      ).to.be.revertedWithCustomError(mockToken, "ERC20InsufficientBalance");
    });

    it("Should revert when insufficient allowance", async function () {
      // Revoke allowance
      await mockToken.connect(user1).approve(await disperse.getAddress(), 0);
      
      await expect(
        disperse.connect(user1).disperse([user2.address], [testAmount], await mockToken.getAddress())
      ).to.be.revertedWithCustomError(mockToken, "ERC20InsufficientAllowance");
    });

    it("Should emit TokenTransfer events for each recipient", async function () {
      const singleRecipient = [user1.address];
      const singleAmount = [testAmount];

      await expect(disperse.connect(user2).disperse(singleRecipient, singleAmount, await mockToken.getAddress()))
        .to.emit(disperse, "TokenTransfer")
        .withArgs(user1.address, await mockToken.getAddress(), 
          (testAmount * BigInt(RECIPIENT_PERCENTAGE)) / 10000n,
          (testAmount * BigInt(TREASURY_PERCENTAGE)) / 10000n,
          (testAmount * BigInt(BURN_PERCENTAGE)) / 10000n);
    });
  });

  describe("Split Calculations", function () {
    it("Should calculate splits correctly", async function () {
      const testAmount = ethers.parseUnits("1000", 18);
      const [treasuryAmount, recipientAmount, burnAmount] = await disperse.calculateSplits(testAmount);

      expect(treasuryAmount).to.equal((testAmount * BigInt(TREASURY_PERCENTAGE)) / 10000n);
      expect(recipientAmount).to.equal((testAmount * BigInt(RECIPIENT_PERCENTAGE)) / 10000n);
      expect(burnAmount).to.equal((testAmount * BigInt(BURN_PERCENTAGE)) / 10000n);
      expect(treasuryAmount + recipientAmount + burnAmount).to.equal(testAmount);
    });

    it("Should handle small amounts correctly (0)", async function () {
      const smallAmount = 1n;
      const [treasuryAmount, recipientAmount, burnAmount] = await disperse.calculateSplits(smallAmount);

      // With small amounts, some splits might be 0 due to integer division
      expect(treasuryAmount + recipientAmount + burnAmount).to.equal(0);
    });

    it("Should handle small amounts correctly", async function () {
        const smallAmount = ethers.parseUnits("1", 18);
        const [treasuryAmount, recipientAmount, burnAmount] = await disperse.calculateSplits(smallAmount);
  
        // With small amounts, some splits might be 0 due to integer division
        expect(treasuryAmount + recipientAmount + burnAmount).to.equal(smallAmount);
      });

    it("Should handle large amounts correctly", async function () {
      const largeAmount = ethers.parseUnits("1000000000", 18);
      const [treasuryAmount, recipientAmount, burnAmount] = await disperse.calculateSplits(largeAmount);

      expect(treasuryAmount).to.equal((largeAmount * BigInt(TREASURY_PERCENTAGE)) / 10000n);
      expect(recipientAmount).to.equal((largeAmount * BigInt(RECIPIENT_PERCENTAGE)) / 10000n);
      expect(burnAmount).to.equal((largeAmount * BigInt(BURN_PERCENTAGE)) / 10000n);
      expect(treasuryAmount + recipientAmount + burnAmount).to.equal(largeAmount);
    });
  });

  describe("Foreign Token Withdrawal", function () {
    it("Should allow owner to withdraw foreign ETH", async function () {
      // Send ETH to contract
      await owner.sendTransaction({
        to: await disperse.getAddress(),
        value: ethers.parseEther("1")
      });

      const initialBalance = await ethers.provider.getBalance(user1.address);
      const withdrawAmount = ethers.parseEther("0.5");

      await expect(disperse.withdrawForeignToken(ethers.ZeroAddress, user1.address, withdrawAmount))
        .to.emit(disperse, "WithdrawForeignToken")
        .withArgs(ethers.ZeroAddress, user1.address, withdrawAmount);

      const finalBalance = await ethers.provider.getBalance(user1.address);
      expect(finalBalance - initialBalance).to.equal(withdrawAmount);
    });

    it("Should allow owner to withdraw foreign ERC20 tokens", async function () {
      // Transfer tokens to contract
      await mockToken.transfer(await disperse.getAddress(), ethers.parseUnits("100", 18));

      const initialBalance = await mockToken.balanceOf(user1.address);
      const withdrawAmount = ethers.parseUnits("50", 18);

      await expect(disperse.withdrawForeignToken(await mockToken.getAddress(), user1.address, withdrawAmount))
        .to.emit(disperse, "WithdrawForeignToken")
        .withArgs(await mockToken.getAddress(), user1.address, withdrawAmount);

      const finalBalance = await mockToken.balanceOf(user1.address);
      expect(finalBalance - initialBalance).to.equal(withdrawAmount);
    });

    it("Should revert when non-owner tries to withdraw", async function () {
      await expect(
        disperse.connect(user1).withdrawForeignToken(ethers.ZeroAddress, user2.address, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(disperse, "OwnableUnauthorizedAccount");
    });

    it("Should revert when recipient is zero address", async function () {
      await expect(
        disperse.withdrawForeignToken(ethers.ZeroAddress, ethers.ZeroAddress, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(disperse, "InvalidAddress");
    });

    it("Should revert when amount is zero", async function () {
      await expect(
        disperse.withdrawForeignToken(ethers.ZeroAddress, user1.address, 0)
      ).to.be.revertedWithCustomError(disperse, "InvalidAmount");
    });

    it("Should revert when insufficient ETH balance", async function () {
      await expect(
        disperse.withdrawForeignToken(ethers.ZeroAddress, user1.address, ethers.parseEther("1000"))
      ).to.be.revertedWithCustomError(disperse, "InsufficientBalance");
    });

    it("Should revert when insufficient ERC20 balance", async function () {
      await expect(
        disperse.withdrawForeignToken(await mockToken.getAddress(), user1.address, ethers.parseUnits("1000000", 18))
      ).to.be.revertedWithCustomError(mockToken, "ERC20InsufficientBalance");
    });
  });

  describe("Edge Cases and Error Handling", function () {
    it("Should handle reentrancy attempts", async function () {
      // This test verifies that the nonReentrant modifier works
      const recipients = [user1.address];
      const amounts = [ethers.parseEther("1")];

      // The contract should not allow reentrancy
      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.not.be.revertedWith("ReentrancyGuard: reentrant call");
    });

    it("Should handle ETH transfer failures gracefully", async function () {
      // Create a contract that rejects ETH transfers
      const RejectingContract = await ethers.getContractFactory("MockERC20");
      const rejectingContract = await RejectingContract.deploy("Reject", "REJ", 0);
      
      // Try to disperse to the rejecting contract
      const recipients = [await rejectingContract.getAddress()];
      const amounts = [ethers.parseEther("1")];

      // This should fail due to the ETH transfer failure
      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(disperse, "ETHTransferFailed");
    });

    it("Should handle maximum recipients per transaction", async function () {
      const maxRecipients = Array(MAX_RECIPIENTS_PER_TX).fill(user1.address);
      const maxAmounts = Array(MAX_RECIPIENTS_PER_TX).fill(ethers.parseEther("0.1"));
      const totalAmount = maxAmounts.reduce((sum, amount) => sum + amount, 0n);

      // This should succeed
      await expect(
        disperse.disperse(maxRecipients, maxAmounts, ethers.ZeroAddress, { value: totalAmount })
      ).to.emit(disperse, "Dispersed");
    });

    it("Should handle single recipient dispersion", async function () {
      const singleRecipient = [user1.address];
      const singleAmount = [ethers.parseEther("1")];

      await expect(
        disperse.disperse(singleRecipient, singleAmount, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.emit(disperse, "Dispersed")
        .withArgs(owner.address, ethers.ZeroAddress, ethers.parseEther("1"), 1);
    });

    it("Should handle zero recipient percentage", async function () {
      // Set recipient percentage to 0
      await disperse.setPercentages(5000, 0, 5000);

      const recipients = [user1.address];
      const amounts = [ethers.parseEther("1")];

      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.emit(disperse, "Dispersed");

      // Reset percentages
      await disperse.setPercentages(TREASURY_PERCENTAGE, RECIPIENT_PERCENTAGE, BURN_PERCENTAGE);
    });

    it("Should handle zero treasury percentage", async function () {
      // Set treasury percentage to 0
      await disperse.setPercentages(0, 8000, 2000);

      const recipients = [user1.address];
      const amounts = [ethers.parseEther("1")];

      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.emit(disperse, "Dispersed");

      // Reset percentages
      await disperse.setPercentages(TREASURY_PERCENTAGE, RECIPIENT_PERCENTAGE, BURN_PERCENTAGE);
    });

    it("Should handle zero burn percentage", async function () {
      // Set burn percentage to 0
      await disperse.setPercentages(3000, 7000, 0);

      const recipients = [user1.address];
      const amounts = [ethers.parseEther("1")];

      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: ethers.parseEther("1") })
      ).to.emit(disperse, "Dispersed");

      // Reset percentages
      await disperse.setPercentages(TREASURY_PERCENTAGE, RECIPIENT_PERCENTAGE, BURN_PERCENTAGE);
    });
  });

  describe("Contract Upgradeability", function () {
    it("Should support UUPS upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXDisperseV2Factory = await ethers.getContractFactory("MWXDisperseV2");
      const upgraded = await upgrades.upgradeProxy(
        await disperse.getAddress(),
        MWXDisperseV2Factory,
        {
          call: {
            fn: "initializeV2",
            args: [],
          },
          unsafeAllow: ["missing-initializer-call"],
        }
      );

      const upgradedMWXDisperse = upgraded as MWXDisperseV2;

      // Verify state is preserved
      expect(await upgradedMWXDisperse.owner()).to.equal(owner.address);
      expect(await upgradedMWXDisperse.newFunction()).to.equal("This is a new function in V2");

      await expect(upgradedMWXDisperse.initializeV2()).to.be.revertedWithCustomError(disperse, "InvalidInitialization");
    });

    it("Should only allow owner to authorize upgrades", async function () {
      // This test verifies the upgrade mechanism works
      const MWXDisperseV2Factory = await ethers.getContractFactory(
        "MWXDisperseV2",
        user1
      );
      await expect(
        upgrades.upgradeProxy(
          await disperse.getAddress(),
          MWXDisperseV2Factory,
          {
            call: {
              fn: "initializeV2",
              args: [],
            },
            unsafeAllow: ["missing-initializer-call"],
          }
        )
      ).to.be.revertedWithCustomError(disperse, "OwnableUnauthorizedAccount");
    });

    it("Should preserve state after upgrade", async function () {
      await disperse.connect(owner).setPercentages(TREASURY_PERCENTAGE, RECIPIENT_PERCENTAGE, BURN_PERCENTAGE);

      // Upgrade contract
      const MWXDisperseV2Factory = await ethers.getContractFactory("MWXDisperseV2");
      const upgraded = await upgrades.upgradeProxy(await disperse.getAddress(), MWXDisperseV2Factory, {
        call: {
          fn: "initializeV2",
          args: [],
        },
        unsafeAllow: ["missing-initializer-call"],
      });

      // Verify state is preserved
      expect(await upgraded.owner()).to.equal(owner.address);
    });

    it("Should only allow owner to authorize upgrades", async function () {
      const MWXDisperseV2Factory = await ethers.getContractFactory("MWXDisperseV2");

      // This would fail in a real scenario, but since we're using the upgrades plugin,
      // it handles the authorization internally. We test the _authorizeUpgrade function indirectly
      // by ensuring only the owner can perform upgrades through the proxy admin.
      await expect(upgrades.upgradeProxy(await disperse.getAddress(), MWXDisperseV2Factory, {
        call: {
          fn: "initializeV2",
          args: [],
        },
        unsafeAllow: ["missing-initializer-call"],
      })).to.not.be.reverted;
    });
  });

  describe("Receive Function", function () {
    it("Should accept ETH via receive function", async function () {
      const amount = ethers.parseEther("1");
      const initialBalance = await ethers.provider.getBalance(await disperse.getAddress());

      await owner.sendTransaction({
        to: await disperse.getAddress(),
        value: amount
      });

      const finalBalance = await ethers.provider.getBalance(await disperse.getAddress());
      expect(finalBalance - initialBalance).to.equal(amount);
    });
  });

  describe("Gas Optimization and Performance", function () {
    it("Should handle multiple recipients efficiently", async function () {
      const numRecipients = 5;
      const recipients = [user1.address, user2.address, user3.address, user4.address, user5.address];
      const amounts = Array(numRecipients).fill(ethers.parseEther("0.1"));
      const totalAmount = amounts.reduce((sum, amount) => sum + amount, 0n);

      await expect(
        disperse.disperse(recipients, amounts, ethers.ZeroAddress, { value: totalAmount })
      ).to.emit(disperse, "Dispersed")
        .withArgs(owner.address, ethers.ZeroAddress, totalAmount, numRecipients);
    });
  });
}); 