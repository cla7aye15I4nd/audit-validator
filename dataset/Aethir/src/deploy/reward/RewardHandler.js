module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const Registry = (await deployments.get("Registry")).address

  await deploy("RewardHandler", {
    from: deployer,
    args: [Registry],
    log: true,
  })
}

module.exports.tags = ["RewardHandler"]
module.exports.dependencies = ["Registry"]