module.exports = async ({ getNamedAccounts, deployments, getChainId, getUnnamedAccounts }) => {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const res = await deploy('SwapInfoManager', {
    from: deployer,
    gasLimit: 400000000,
    tags: 'info',
  })
  console.log(res)
}

module.exports.tags = ['info']
