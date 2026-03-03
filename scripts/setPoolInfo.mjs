import { initTronWeb } from './tron.mjs';
import config from './config.js';
const { mainnet, nile } = config;

let StableInfoABI = [
  {
    "inputs": [],
    "stateMutability": "nonpayable",
    "type": "constructor"
  },
  {
    "anonymous": false,
    "inputs": [
      {
        "indexed": true,
        "internalType": "address",
        "name": "previousOwner",
        "type": "address"
      },
      {
        "indexed": true,
        "internalType": "address",
        "name": "newOwner",
        "type": "address"
      }
    ],
    "name": "OwnershipTransferred",
    "type": "event"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "input",
        "type": "address"
      },
      {
        "internalType": "address",
        "name": "output",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "flag",
        "type": "uint256"
      }
    ],
    "name": "getStableInfo",
    "outputs": [
      {
        "internalType": "uint256",
        "name": "k",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "j",
        "type": "uint256"
      },
      {
        "internalType": "address",
        "name": "swapContract",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "extension",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "flag",
        "type": "uint256"
      }
    ],
    "name": "getSwapPoolInfo",
    "outputs": [
      {
        "components": [
          {
            "internalType": "address",
            "name": "swapContract",
            "type": "address"
          },
          {
            "internalType": "address[]",
            "name": "tokens",
            "type": "address[]"
          },
          {
            "internalType": "address",
            "name": "LPContract",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "extension",
            "type": "uint256"
          }
        ],
        "internalType": "struct SwapInfoManager.SwapPoolInfo",
        "name": "",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "operator",
    "outputs": [
      {
        "internalType": "address",
        "name": "",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "owner",
    "outputs": [
      {
        "internalType": "address",
        "name": "",
        "type": "address"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "_operator",
        "type": "address"
      }
    ],
    "name": "setOperator",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "flag",
        "type": "uint256"
      },
      {
        "internalType": "address",
        "name": "swapContract",
        "type": "address"
      },
      {
        "internalType": "address[]",
        "name": "tokens",
        "type": "address[]"
      },
      {
        "internalType": "address",
        "name": "LPContract",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "extension",
        "type": "uint256"
      }
    ],
    "name": "setSwapPoolInfo",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "",
        "type": "uint256"
      }
    ],
    "name": "swapPoolInfo",
    "outputs": [
      {
        "internalType": "address",
        "name": "swapContract",
        "type": "address"
      },
      {
        "internalType": "address",
        "name": "LPContract",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "extension",
        "type": "uint256"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "_operator",
        "type": "address"
      }
    ],
    "name": "transferOperator",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "address",
        "name": "newOwner",
        "type": "address"
      }
    ],
    "name": "transferOwnership",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
]
const cfg = nile;
const tronWeb = await initTronWeb(cfg);


const infoImp = await tronWeb.contract(StableInfoABI, cfg.stableSwapInfo);
// flag = 0x10001, htxsunswap

// function setSwapPoolInfo(
//   uint256 index,
//   address swapContract,
//   address[] calldata tokens,
//   address LPContract,
//   uint256 extension
// )

await infoImp.setSwapPoolInfo(0x10001, cfg.HtxSunSwapTest, [cfg.HTXtest, cfg.SUNtest], cfg.HtxSunSwapTest, 0).send();
// flag = 0x10010, psm

await infoImp.setSwapPoolInfo(0x10010, cfg.usdt20psmpool.psm, [cfg.usdd20Token, cfg.usdt20Token], cfg.usdtpsmpool.gemJoin, 1e12).send();
// flag = 0x10100, usdd202pool
await infoImp.setSwapPoolInfo(0x10100, cfg.usdd202Pool, [cfg.usdd20Token, cfg.usdt20Token], cfg.usdd202Pool, 0).send();

// flag = 0x20100, usdd2pool
await infoImp.setSwapPoolInfo(0x20100, cfg.usdd2pool, [cfg.usddToken, cfg.usdtToken], cfg.usdd2pool, 0).send();
// flag = 0x30100, tusdusdt2pool
await infoImp.setSwapPoolInfo(0x30100, cfg.tusdusdt2pool, [cfg.tusdToken, cfg.usdtToken], cfg.tusdusdt2pool, 0).send();
// flag = 0x40100, old3pool
await infoImp.setSwapPoolInfo(0x40100, cfg.old3pool, [cfg.usdjToken, cfg.tusdToken, cfg.usdtToken], cfg.old3pool, 0).send();
// flag = 0x11000, oldusdcpool
await infoImp.setSwapPoolInfo(0x11000, cfg.oldusdcpool, [cfg.usdcToken, cfg.usdjToken, cfg.tusdToken, cfg.usdtToken], cfg.oldusdcpool, 0).send();
// flag = 0x21000, usdc2pooltusdusdt
await infoImp.setSwapPoolInfo(0x21000, cfg.usdc2pooltusdusdt, [cfg.usdcToken, cfg.tusdToken, cfg.usdtToken], cfg.usdc2pooltusdusdt, 0).send();
// flag = 0x31000, usdd2pooltusdusdt
await infoImp.setSwapPoolInfo(0x31000, cfg.usdd2pooltusdusdt, [cfg.usddToken, cfg.tusdToken, cfg.usdtToken], cfg.usdd2pooltusdusdt, 0).send();
// flag = 0x41000, usdj2pooltusdusdt
await infoImp.setSwapPoolInfo(0x41000, cfg.usdj2pooltusdusdt, [cfg.usdjToken, cfg.tusdToken, cfg.usdtToken], cfg.usdj2pooltusdusdt, 0).send();

console.log("set pool info done");


// address[] memory usdcTokens = new address[](4);
// usdcTokens[0] = _usdc;
// usdcTokens[1] = _usdj;
// usdcTokens[2] = _tusd;
// usdcTokens[3] = _usdt;
// addUsdcPool("oldusdcpool", _usdcPool, usdcTokens);
// address[] memory old3PoolTokens = new address[](3);
// old3PoolTokens[0] = _usdj;
// old3PoolTokens[1] = _tusd;
// old3PoolTokens[2] = _usdt;
// addPool("old3pool", _old3pool, old3PoolTokens);