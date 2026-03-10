module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  await deploy("AethirToken", {
    from: deployer,
    args: [],
    log: true,
  })
}

module.exports.skip = ({ getNamedAccounts }) =>
  new Promise(async (resolve, reject) => {
    try {
      const { deployer, token } = await getNamedAccounts()
      // only deploy mock token if we don't have a real token
      resolve(token != deployer)
    } catch (error) {
      reject(error)
    }
  })

module.exports.tags = ["AethirToken"]