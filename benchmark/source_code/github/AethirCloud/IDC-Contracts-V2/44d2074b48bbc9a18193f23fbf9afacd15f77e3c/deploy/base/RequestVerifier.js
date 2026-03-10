module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const Registry = (await deployments.get("Registry")).address

  await deploy("RequestVerifier", {
    from: deployer,
    args: [Registry],
    log: true,
  })
}

module.exports.tags = ["RequestVerifier"]
module.exports.dependencies = ["Registry"]