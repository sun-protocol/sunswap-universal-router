module.exports = async ({ getNamedAccounts, deployments, getChainId, getUnnamedAccounts }) => {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  // address permit2;
  // address weth9;
  // PERMIT2 = IPermit2(params.permit2);
  // WETH9 = IWETH9(params.weth9);
  // SUNSWAP_V1_FACTORY = params.v1Factory;
  // PANCAKESWAP_V2_FACTORY = params.v2Factory;
  // PANCAKESWAP_V2_PAIR_INIT_CODE_HASH = params.v2InitCodeHash;
  // PANCAKESWAP_V3_FACTORY = params.v3Factory;
  // PANCAKESWAP_V3_POOL_INIT_CODE_HASH = params.v3InitCodeHash;
  // PANCAKESWAP_V3_DEPLOYER = params.v3Deployer;
  // V3_POSITION_MANAGER = IV3NonfungiblePositionManager(params.v3NFTPositionManager);
  // INFI_CL_POSITION_MANAGER = IPositionManager(params.infiClPositionManager);

  const params = {
    permit2: '0xF62F506D1FAA02E2354A9886B4A200496EE96F4B',
    weth9: '0xFB3B3134F13CCD2C81F4012E53024E8135D58FEE',
    v1Factory: '0xE97E6EE12D3DB8176242BB901FDB924CC938E2D9',
    v2Factory: '0x55F7D5D874A73F21C0851C62D374307985F440FC',
    v3Factory: '0xCAC0EE410E19A12CCE8805D5374BB60200FADD03',
    v3Deployer: '0xCAC0EE410E19A12CCE8805D5374BB60200FADD03',
    v2InitCodeHash: '0x9dd9bfc2f6c1103a6c01d9c6a4044e4b8a9361f92df2728cdc3729922d56748e',
    v3InitCodeHash: '0xbdafe9a36668104a2d371dedf31aac9583722f1b2c2fe98dde229f50a1e81689',
    stableFactory: '0x47E67AAF9106401F553AE649F50D07D780EB70DE',
    stableInfo: '0x47E67AAF9106401F553AE649F50D07D780EB70DE',
    v4Vault: '0xD8AEC7918153470DA1C6CFE464063B590CEEC8B6',
    v4ClPoolManager: '0xD8AEC7918153470DA1C6CFE464063B590CEEC8B6',
    v3NFTPositionManager: '0x937A4ADE5E502DAAD2F640B58E0346FF5A13A01F',
    v4ClPositionManager: '0x7DFE36F4916E434C020405EBB6E7CDE0B9673CC7', //TUrtUhPsLRQNYJRPBjyCh7a8zcMmwrrFTi
  }
  // the following will only deploy "GenericMetaTxProcessor" if the contract was never deployed or if the code changed since last deployment
  const res = await deploy('UniversalRouter', {
    from: deployer,
    gasLimit: 400000000,
    args: [params],
    tags: 'lumi',
  })
  console.log(res)
}

module.exports.tags = ['lumi']
