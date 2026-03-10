import { ethers, getNamedAccounts } from "hardhat";
import { expect } from "chai";
import { deployments } from "hardhat";

describe("Impersonation Test", function () {
	beforeEach(async function () {
		// This will run the specified deployment scripts before each test
		// If you want to run all deployment scripts, just pass 'all'
		await deployments.fixture("all");

		// Now, your contracts are deployed, and you can interact with them
		const { deployer } = await getNamedAccounts();
		// Use deployer or other named accounts as needed
	});
	it("Should impersonate an account", async function () {
		const targetAddress = "0x3ba519C4C857Ef20ED3fA646DC432f46Edd688f1"; // Address you want to impersonate
		// Start impersonating the account
		await ethers.provider.send("hardhat_impersonateAccount", [targetAddress]);
		// Get a signer for the impersonated account
		const impersonatedSigner = await ethers.getSigner(targetAddress);

		// Now you can use impersonatedSigner to send transactions or query balances
		// Example: Checking the balance
		const balance = await ethers.provider.getBalance(impersonatedSigner);
		console.log(
			`Balance of impersonated account: ${ethers.formatEther(balance)} ETH`
		);

		// Optionally, you can add test conditions
		expect(balance).to.be.above(ethers.parseEther("0"));

		// Stop impersonating the account
		await ethers.provider.send("hardhat_stopImpersonatingAccount", [
			targetAddress,
		]);
	});

	// it("testing 1 2 3", async function () {
	// 	await deployments.fixture(["Facets"]);
	// 	const Token = await deployments.get("Token"); // Token is available because the fixture was executed
	// 	console.log(Token.address);
	// 	const ERC721BidSale = await deployments.get("ERC721BidSale");
	// 	console.log({ ERC721BidSale });
	// });
});
