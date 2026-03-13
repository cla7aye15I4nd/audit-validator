import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MWXT, MWXTV2 } from "../typechain-types";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("MWXT Token Contract", function () {
  let mwxt: MWXT;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addrs: SignerWithAddress[];

  // Token parameters
  const TOKEN_NAME = "MWXT Token";
  const TOKEN_SYMBOL = "MWXT";
  const INITIAL_SUPPLY = 100000; // 100K tokens
  const DECIMALS = 18;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    // Deploy the upgradeable contract
    const MWXTFactory = await ethers.getContractFactory("MWXT");
    mwxt = (await upgrades.deployProxy(MWXTFactory, [
      TOKEN_NAME,
      TOKEN_SYMBOL,
      INITIAL_SUPPLY,
      owner.address,
    ])) as unknown as MWXT;

    await mwxt.waitForDeployment();
  });

  describe("Deployment and Initialization", function () {
    it("Should set the right token name and symbol", async function () {
      expect(await mwxt.name()).to.equal(TOKEN_NAME);
      expect(await mwxt.symbol()).to.equal(TOKEN_SYMBOL);
    });

    it("Should set the right decimals", async function () {
      expect(await mwxt.decimals()).to.equal(DECIMALS);
    });

    it("Should mint initial supply to owner", async function () {
      const expectedSupply = ethers.parseUnits(INITIAL_SUPPLY.toString(), DECIMALS);
      expect(await mwxt.totalSupply()).to.equal(expectedSupply);
      expect(await mwxt.balanceOf(owner.address)).to.equal(expectedSupply);
    });

    it("Should set the right owner", async function () {
      expect(await mwxt.owner()).to.equal(owner.address);
    });

    it("Should return correct version", async function () {
      expect(await mwxt.version()).to.equal("1");
    });

    it("Should not be paused initially", async function () {
      expect(await mwxt.paused()).to.be.false;
    });

    it("Should not mint initial supply if initial supply is 0", async function () {
        const MWXTFactory = await ethers.getContractFactory("MWXT");
        const deployedMWXT = await upgrades.deployProxy(MWXTFactory, [
            TOKEN_NAME,
            TOKEN_SYMBOL,
            0, // Zero initial supply
            owner.address,
        ]);

        const mwxt = deployedMWXT as MWXT;
        expect(await mwxt.totalSupply()).to.equal(0);
      });

    it("Should fail initialization with zero owner address", async function () {
      const MWXTFactory = await ethers.getContractFactory("MWXT");
      await expect(
        upgrades.deployProxy(MWXTFactory, [
          TOKEN_NAME,
          TOKEN_SYMBOL,
          ethers.parseUnits("100000", 0),
          ethers.ZeroAddress,
        ])
      ).to.be.revertedWithCustomError(mwxt, "InvalidAddress");
    });

    it("Should fail when calling initialize", async function () {
      await expect(
        mwxt.initialize(
          TOKEN_NAME, 
          TOKEN_SYMBOL, 
          INITIAL_SUPPLY, 
          owner.address
        )
      ).to.be.revertedWithCustomError(mwxt, "InvalidInitialization");
    });

    it("Should not allow minting after initialization", async function () {
      // The contract should not have a mint function
      expect('mint' in mwxt).to.be.false;
    });
  });

  describe("ERC20 Basic Functionality", function () {
    it("Should transfer tokens between accounts", async function () {
      const transferAmount = ethers.parseUnits("1000", DECIMALS);
      const initialSupply = ethers.parseUnits(INITIAL_SUPPLY.toString(), DECIMALS);
      
      await mwxt.transfer(addr1.address, transferAmount);
      expect(await mwxt.balanceOf(addr1.address)).to.equal(transferAmount);
      expect(await mwxt.balanceOf(owner.address)).to.equal(initialSupply - transferAmount);
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      await expect(
        mwxt.connect(addr1).transfer(owner.address, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(mwxt, "ERC20InsufficientBalance");
    });

    it("Should update allowances on approval", async function () {
      const approvalAmount = ethers.parseUnits("1000", DECIMALS);
      
      await mwxt.approve(addr1.address, approvalAmount);
      expect(await mwxt.allowance(owner.address, addr1.address)).to.equal(
        approvalAmount
      );
    });

    it("Should transfer from approved accounts", async function () {
      const approvalAmount = ethers.parseUnits("1000", DECIMALS);
      const transferAmount = ethers.parseUnits("500", DECIMALS);
      
      await mwxt.approve(addr1.address, approvalAmount);
      await mwxt.connect(addr1).transferFrom(owner.address, addr2.address, transferAmount);
      
      expect(await mwxt.balanceOf(addr2.address)).to.equal(transferAmount);
      expect(await mwxt.allowance(owner.address, addr1.address)).to.equal(
        approvalAmount - transferAmount
      );
    });
  });

  describe("ERC20 Permit Functionality", function () {
    it("Should work with permit", async function () {
      const value = ethers.parseUnits("1000", DECIMALS);
      const deadline = (await time.latest()) + 3600; // 1 hour from now
      const nonce = await mwxt.nonces(owner.address);

      // Create domain separator
      const domain = {
        name: TOKEN_NAME,
        version: await mwxt.version(),
        chainId: await ethers.provider.getNetwork().then(n => n.chainId),
        verifyingContract: await mwxt.getAddress(),
      };

      // Create permit type
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      };

      // Create permit message
      const message = {
        owner: owner.address,
        spender: addr1.address,
        value: value,
        nonce: nonce,
        deadline: deadline,
      };

      // Sign the permit
      const signature = await owner.signTypedData(domain, types, message);
      const { v, r, s } = ethers.Signature.from(signature);

      // Execute permit
      await mwxt.permit(owner.address, addr1.address, value, deadline, v, r, s);

      // Check allowance
      expect(await mwxt.allowance(owner.address, addr1.address)).to.equal(value);
    });
  });

  describe("Burnable Functionality", function () {
    beforeEach(async function () {
      // Transfer some tokens to addr1 for burning tests
      await mwxt.transfer(addr1.address, ethers.parseUnits("10000", DECIMALS));
    });

    it("Should burn tokens and reduce total supply", async function () {
      const burnAmount = ethers.parseUnits("1000", DECIMALS);
      const initialSupply = await mwxt.totalSupply();
      const initialBalance = await mwxt.balanceOf(addr1.address);

      await mwxt.connect(addr1).burn(burnAmount);

      expect(await mwxt.totalSupply()).to.equal(initialSupply - burnAmount);
      expect(await mwxt.balanceOf(addr1.address)).to.equal(initialBalance - burnAmount);
    });

    it("Should burn from approved account", async function () {
      const burnAmount = ethers.parseUnits("500", DECIMALS);
      const initialSupply = await mwxt.totalSupply();
      
      // Approve addr2 to burn from addr1
      await mwxt.connect(addr1).approve(addr2.address, burnAmount);
      await mwxt.connect(addr2).burnFrom(addr1.address, burnAmount);

      expect(await mwxt.totalSupply()).to.equal(initialSupply - burnAmount);
    });

    it("Should fail to burn more than balance", async function () {
      const balance = await mwxt.balanceOf(addr1.address);
      const burnAmount = balance + ethers.parseUnits("1", DECIMALS);

      await expect(
        mwxt.connect(addr1).burn(burnAmount)
      ).to.be.revertedWithCustomError(mwxt, "ERC20InsufficientBalance");
    });
  });

  describe("Pausable Functionality", function () {
    it("Should pause and unpause transfers", async function () {
      // Pause the contract
      await mwxt.pause();
      expect(await mwxt.paused()).to.be.true;

      // Try to transfer - should fail
      await expect(
        mwxt.transfer(addr1.address, ethers.parseUnits("100", DECIMALS))
      ).to.be.revertedWithCustomError(mwxt, "EnforcedPause");

      // Unpause the contract
      await mwxt.unpause();
      expect(await mwxt.paused()).to.be.false;

      // Transfer should work now
      await expect(
        mwxt.transfer(addr1.address, ethers.parseUnits("100", DECIMALS))
      ).to.not.be.reverted;
    });

    it("Should only allow owner to pause/unpause", async function () {
      await expect(
        mwxt.connect(addr1).pause()
      ).to.be.revertedWithCustomError(mwxt, "OwnableUnauthorizedAccount");

      await mwxt.pause();
      await expect(
        mwxt.connect(addr1).unpause()
      ).to.be.revertedWithCustomError(mwxt, "OwnableUnauthorizedAccount");
    });
  });


  describe("Ownership Functionality", function () {
    it("Should transfer ownership", async function () {
      await mwxt.transferOwnership(addr1.address);
      expect(await mwxt.owner()).to.equal(addr1.address);
    });

    it("Should renounce ownership", async function () {
      await mwxt.renounceOwnership();
      expect(await mwxt.owner()).to.equal(ethers.ZeroAddress);
    });

    it("Should only allow owner to transfer ownership", async function () {
      await expect(
        mwxt.connect(addr1).transferOwnership(addr2.address)
      ).to.be.revertedWithCustomError(mwxt, "OwnableUnauthorizedAccount");
    });
  });

  describe("Foreign Token Withdrawal", function () {
    let mockToken: any;

    beforeEach(async function () {
      // Deploy a mock ERC20 token for testing
      const MockTokenFactory = await ethers.getContractFactory("MockERC20");
      mockToken = await MockTokenFactory.deploy("Mock Token", "MOCK", ethers.parseEther("1000000"));
      await mockToken.waitForDeployment();

      // Send some mock tokens to the MWXT contract
      await mockToken.transfer(await mwxt.getAddress(), ethers.parseEther("1000"));
      expect(await mockToken.decimals()).to.equal(6);
    });

    it("Should withdraw foreign ERC20 tokens", async function () {
      const withdrawAmount = ethers.parseEther("500");
      const initialBalance = await mockToken.balanceOf(addr1.address);

      await expect(
        mwxt.withdrawForeignToken(await mockToken.getAddress(), addr1.address, withdrawAmount)
      ).to.emit(mwxt, "WithdrawForeignToken").withArgs(await mockToken.getAddress(), addr1.address, withdrawAmount);

      expect(await mockToken.balanceOf(addr1.address)).to.equal(
        initialBalance + withdrawAmount
      );
    });

    it("Should withdraw native tokens (ETH)", async function () {
      // Send some ETH to the contract
      await owner.sendTransaction({
        to: await mwxt.getAddress(),
        value: ethers.parseEther("1"),
      });

      const withdrawAmount = ethers.parseEther("0.5");
      const initialBalance = await ethers.provider.getBalance(addr1.address);

      await expect(
        mwxt.withdrawForeignToken(ethers.ZeroAddress, addr1.address, withdrawAmount)
      ).to.emit(mwxt, "WithdrawForeignToken").withArgs(ethers.ZeroAddress, addr1.address, withdrawAmount);

      const finalBalance = await ethers.provider.getBalance(addr1.address);
      expect(finalBalance - initialBalance).to.equal(withdrawAmount);
    });

    it("Should fail to withdraw more tokens than available", async function () {
      const availableBalance = await mockToken.balanceOf(await mwxt.getAddress());
      const withdrawAmount = availableBalance + ethers.parseEther("1");

      await expect(
        mwxt.withdrawForeignToken(await mockToken.getAddress(), addr1.address, withdrawAmount)
      ).to.be.revertedWithCustomError(mwxt, "ERC20InsufficientBalance");
    });

    it("Should fail to withdraw more ETH than available", async function () {
      const withdrawAmount = ethers.parseEther("10"); // More than contract balance

      await expect(
        mwxt.withdrawForeignToken(ethers.ZeroAddress, addr1.address, withdrawAmount)
      ).to.be.revertedWithCustomError(mwxt, "InsufficientBalance");
    });

    it("Should fail to withdraw 0 amount", async function () {
      const withdrawAmount = ethers.parseEther("0"); // More than contract balance

      await expect(
        mwxt.withdrawForeignToken(ethers.ZeroAddress, addr1.address, withdrawAmount)
      ).to.be.revertedWithCustomError(mwxt, "InvalidAmount");
    });

    it("Should fail to withdraw to zero address", async function () {
      const withdrawAmount = ethers.parseEther("100"); // More than contract balance

      await expect(
        mwxt.withdrawForeignToken(ethers.ZeroAddress, ethers.ZeroAddress, withdrawAmount)
      ).to.be.revertedWithCustomError(mwxt, "InvalidAddress");
    });

    it("Should only allow owner to withdraw foreign tokens", async function () {
      await expect(
        mwxt.connect(addr1).withdrawForeignToken(
          await mockToken.getAddress(),
          addr1.address,
          ethers.parseEther("100")
        )
      ).to.be.revertedWithCustomError(mwxt, "OwnableUnauthorizedAccount");
    });
  });

  describe("Upgradeability", function () {
    it("Should upgrade to new implementation", async function () {
      // Deploy V2 implementation
      const MWXTV2Factory = await ethers.getContractFactory("MWXTV2");
      
      // For testing, we'll just upgrade to the same contract
      // In real scenarios, you'd have a new contract with additional features
      const upgraded = await upgrades.upgradeProxy(await mwxt.getAddress(), MWXTV2Factory, {
        call: {
          fn: "initializeV2",
          args: [],
        },
        unsafeAllow: ["missing-initializer-call"]
      });
      const upgradedMWXT = upgraded as MWXTV2;
      
      // Verify state is preserved
      expect(await upgradedMWXT.name()).to.equal(TOKEN_NAME);
      expect(await upgradedMWXT.symbol()).to.equal(TOKEN_SYMBOL);
      expect(await upgradedMWXT.owner()).to.equal(owner.address);
      expect(await upgradedMWXT.version()).to.equal("2");
      expect(await upgradedMWXT.newFunction()).to.equal("This is a new function in V2");

      await expect(upgradedMWXT.initializeV2()).to.be.revertedWithCustomError(mwxt, "InvalidInitialization");
    });

    it("Should only allow owner to authorize upgrades", async function () {
      // This test would require trying to upgrade from a non-owner account
      // The actual upgrade authorization happens in _authorizeUpgrade
      // which is tested implicitly in the upgrade process
      const MWXTV2Factory = await ethers.getContractFactory("MWXTV2", addr1);
      await expect(upgrades.upgradeProxy(await mwxt.getAddress(), MWXTV2Factory, {
        call: {
          fn: "initializeV2",
          args: [],
        },
        unsafeAllow: ["missing-initializer-call"]
      })).to.be.revertedWithCustomError(mwxt, "OwnableUnauthorizedAccount");
    });
  });

  describe("Edge Cases and Security", function () {
    it("Should handle zero transfers", async function () {
      await expect(mwxt.transfer(addr1.address, 0)).to.not.be.reverted;
    });

    it("Should handle self transfers", async function () {
      const initialBalance = await mwxt.balanceOf(owner.address);
      await mwxt.transfer(owner.address, ethers.parseUnits("100", DECIMALS));
      expect(await mwxt.balanceOf(owner.address)).to.equal(initialBalance);
    });

    it("Should not allow transfers to zero address", async function () {
      await expect(
        mwxt.transfer(ethers.ZeroAddress, ethers.parseUnits("100", DECIMALS))
      ).to.be.revertedWithCustomError(mwxt, "ERC20InvalidReceiver");
    });

    it("Should handle maximum values correctly", async function () {
      // Test with very large numbers (within cap limits)
      const largeAmount = ethers.parseUnits("50000", DECIMALS);
      await expect(mwxt.transfer(addr1.address, largeAmount)).to.not.be.reverted;
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complex scenario: transfer, pause, unpause, burn", async function () {
      const transferAmount = ethers.parseUnits("5000", DECIMALS);
      const burnAmount = ethers.parseUnits("1000", DECIMALS);

      // Transfer tokens
      await mwxt.transfer(addr1.address, transferAmount);
      expect(await mwxt.balanceOf(addr1.address)).to.equal(transferAmount);

      // Pause contract
      await mwxt.pause();
      await expect(
        mwxt.connect(addr1).burn(burnAmount)
      ).to.be.revertedWithCustomError(mwxt, "EnforcedPause");

      // Unpause and burn
      await mwxt.unpause();
      const initialSupply = await mwxt.totalSupply();
      await mwxt.connect(addr1).burn(burnAmount);
      
      expect(await mwxt.totalSupply()).to.equal(initialSupply - burnAmount);
      expect(await mwxt.balanceOf(addr1.address)).to.equal(transferAmount - burnAmount);
    });

    it("Should maintain state consistency across operations", async function () {
      const operations = [
        () => mwxt.transfer(addr1.address, ethers.parseUnits("1000", DECIMALS)),
        () => mwxt.connect(addr1).approve(addr2.address, ethers.parseUnits("500", DECIMALS)),
        () => mwxt.connect(addr2).transferFrom(addr1.address, owner.address, ethers.parseUnits("200", DECIMALS)),
        () => mwxt.connect(addr1).burn(ethers.parseUnits("300", DECIMALS)),
      ];

      for (const operation of operations) {
        await operation();
      }

      // Verify final state
      const totalSupply = await mwxt.totalSupply();
      const ownerBalance = await mwxt.balanceOf(owner.address);
      const addr1Balance = await mwxt.balanceOf(addr1.address);
      const addr2Balance = await mwxt.balanceOf(addr2.address);

      expect(ownerBalance + addr1Balance + addr2Balance).to.equal(totalSupply);
    });
  });
});