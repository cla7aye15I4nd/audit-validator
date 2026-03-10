module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments
  const { deployer, token } = await getNamedAccounts()

  const ACLManager = (await deployments.get("ACLManager")).address
  let AethirToken
  if (token != deployer) {
    AethirToken = token
  } else {
    AethirToken = (await deployments.get("AethirToken")).address
  }

  await deploy("Registry", {
    from: deployer,
    args: [ACLManager, AethirToken],
    log: true,
  })
}

module.exports.tags = ["Registry"]
module.exports.dependencies = ["ACLManager", "AethirToken"]