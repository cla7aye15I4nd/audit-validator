const { task } = require("hardhat/config")
const { BigNumber } = require('ethers')

task('accounts', 'Prints the list of accounts', async (_args, hre) => {
	const accounts = await hre.ethers.getSigners();
	for (const account of accounts) {
		console.log(account.address);
	}
});

task("initialize", "Initialize")
	.setAction(async ({ }, hre) => {
		const registryAddress = (await hre.deployments.get("Registry")).address
		console.log('Registry Address:', registryAddress)
		const registry = await hre.ethers.getContractAt('Registry', registryAddress)
		console.log(await registry.initialize([], []))
	})

task("verifyAll", "Verify all contracts").setAction(async ({}, hre) => {
	const deployments = await hre.deployments.all();
	for (const name in deployments) {
	  const deployment = deployments[name];
	  try {
		await hre.run("verify:verify", {
		  address: deployment.address,
		  constructorArguments: deployment.args,
		  noCompile: true,
		});
	  } catch (e) {
		if (e.message.includes("Contract source code already verified")) {
			console.log("Already verified", name, "at", deployment.address);
			continue
		}
		console.log(name, e);
	  }
	}
});

task("services", "List service addresses")
	.setAction(async ({ }, hre) => {
		const registryAddress = (await hre.deployments.get("Registry")).address
		const registry = await hre.ethers.getContractAt('Registry', registryAddress)
		const listAddress = (await hre.deployments.get("ServiceIdList")).address
		const list = await hre.ethers.getContractAt('ServiceIdList', listAddress)

		const print = async (serviceName) => {
			const serviceId = await list[serviceName]()
			const address = await registry.getFunction("getAddress")(serviceId)
			console.log(serviceName, serviceId, address)
		}

		const all = [
			"ACCOUNT_HANDLER_ID",
			"ACCOUNT_STORAGE_ID",
			"REQUEST_VERIFIER_ID",
			"USER_STORAGE_ID",
			"REWARD_COMMISSION_RECEIVER_ID",
			"REWARD_CONFIGURATOR_ID",
			"REWARD_HANDLER_ID",
			"REWARD_FUND_HOLDER_ID",
			"REWARD_STORAGE_ID",
			"BLACKLIST_MANAGER_ID",
			"EMERGENCY_SWITCH_ID",
			"TIER_CONTROLLER_ID",
			"GRANT_POOL_ID",
			"SERVICE_FEE_COMMISSION_RECEIVER_ID",
			"SERVICE_FEE_HANDLER_ID",
			"SERVICE_FEE_STORAGE_ID",
			"SERVICE_FEE_FUND_HOLDER_ID",
			"SERVICE_FEE_CONFIGURATOR_ID",
			"SLASH_CONFIGURATOR_ID",
			"SLASH_DEDUCTION_RECEIVER_ID",
			"SLASH_HANDLER_ID",
			"SLASH_STORAGE_ID",
			"TICKET_MANAGER_ID",
			"RESTAKE_FEE_RECEIVER_ID",
			"STAKE_CONFIGURATOR_ID",
			"STAKE_FUND_HOLDER_ID",
			"STAKE_HANDLER_ID",
			"STAKE_STORAGE_ID",
			"VESTING_CONFIGURATOR_ID",
			"VESTING_PENALTY_RECEIVER_ID",
			"VESTING_PENALTY_MANAGER_ID",
			"VESTING_SCHEME_MANAGER_ID",
			"VESTING_STORAGE_ID",
			"VESTING_FUND_HOLDER_ID",
			"VESTING_HANDLER_ID",
			"KYC_WHITELIST_ID"
		]
		for (const serviceName of all) {
			await print(serviceName)
		}
	})

task("methods", "List method ids")
	.setAction(async ({ }, hre) => {
		const listAddress = (await hre.deployments.get("MethodIdList")).address
		const list = await hre.ethers.getContractAt('MethodIdList', listAddress)

		const print = async (methodName) => {
			const methodId = await list[methodName]()
			console.log(methodName, methodId)
		}

		const all = [
			"CREATE_ACCOUNT",
			"REBIND_WALLET",
			"CREATE_GROUP",
			"ASSIGN_DELEGATOR",
			"REVOKE_DELEGATOR",
			"SET_FEE_RECEIVER",
			"REVOKE_FEE_RECEIVER",
			"SET_REWARD_RECEIVER",
			"REVOKE_REWARD_RECEIVER",
			"INITIAL_ACCOUNT_MIGRATION",
			"BATCH_UPDATE_GROUP_SETTINGS",
			"BATCH_SET_RECEIVERS",
			"UPDATE_KYC",
			"SET_REWARD_EMISSION_SCHEDULE",
			"SETTLE_REWARD",
			"INITIAL_SETTLE_REWARD",
			"LOCK_SERVICE_FEE",
			"UNLOCK_SERVICE_FEE",
			"SETTLE_SERVICE_FEE",
			"INITIAL_SETTLE_SERVICE_FEE",
			"INITIAL_TENANTS_SERVICE_FEE",
			"ADD_PENALTY",
			"SETTLE_PENALTY",
			"DEDUCT_PENALTY",
			"CANCEL_PENALTY",
			"REFUND_TENANTS",
			"STAKE",
			"DELEGATION_STAKE",
			"UNSTAKE",
			"DELEGATION_UNSTAKE",
			"FORCE_UNSTAKE",
			"INITIAL_SETTLE_STAKING",
			"INITIAL_SETTLE_VESTING"
		]
		for (const methodName of all) {
			await print(methodName)
		}
	})
