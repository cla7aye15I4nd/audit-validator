module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments
  const { deployer, admin } = await getNamedAccounts()

  await deploy('ACLManager', {
    from: deployer,
    args: [admin],
    log: true,
  })
}

module.exports.tags = ['ACLManager']
