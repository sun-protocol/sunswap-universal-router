import { initTronWeb } from './tron.mjs';
import config from './config.js';
const { mainnet, nile } = config;

let StableInfoABI = [
   
    {
      "inputs": [],
      "name": "acceptOwnership",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "",
          "type": "address"
        }
      ],
      "name": "exactSwapPairInfo",
      "outputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
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
          "name": "input",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "output",
          "type": "address"
        }
      ],
      "name": "getExactSwapPairInfo",
      "outputs": [
        {
          "components": [
            {
              "internalType": "address",
              "name": "swapContract",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token0",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token1",
              "type": "address"
            }
          ],
          "internalType": "struct StableSwapInfo.ExactSwapPairInfo",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
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
        }
      ],
      "name": "getPSMSwapPairInfo",
      "outputs": [
        {
          "components": [
            {
              "internalType": "address",
              "name": "swapContract",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token0",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token1",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "LPContract",
              "type": "address"
            },
            {
              "internalType": "uint256",
              "name": "psmRelativeDecimals",
              "type": "uint256"
            }
          ],
          "internalType": "struct StableSwapInfo.PSMSwapPairInfo",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
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
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        }
      ],
      "name": "getStableSwapFourPoolPairInfo",
      "outputs": [
        {
          "components": [
            {
              "internalType": "address",
              "name": "swapContract",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token0",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token1",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token2",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token3",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "LPContract",
              "type": "address"
            }
          ],
          "internalType": "struct StableSwapInfo.StableSwapFourPoolPairInfo",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        }
      ],
      "name": "getStableSwapPairInfo",
      "outputs": [
        {
          "components": [
            {
              "internalType": "address",
              "name": "swapContract",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token0",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token1",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "LPContract",
              "type": "address"
            }
          ],
          "internalType": "struct StableSwapInfo.StableSwapPairInfo",
          "name": "",
          "type": "tuple"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        }
      ],
      "name": "getStableSwapThreePoolPairInfo",
      "outputs": [
        {
          "components": [
            {
              "internalType": "address",
              "name": "swapContract",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token0",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token1",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "token2",
              "type": "address"
            },
            {
              "internalType": "address",
              "name": "LPContract",
              "type": "address"
            }
          ],
          "internalType": "struct StableSwapInfo.StableSwapThreePoolPairInfo",
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
      "inputs": [],
      "name": "pendingOwner",
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
          "name": "",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "",
          "type": "address"
        }
      ],
      "name": "psmSwapPairInfo",
      "outputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "psmRelativeDecimals",
          "type": "uint256"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "renounceOwnership",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        }
      ],
      "name": "setExactSwapPairInfo",
      "outputs": [],
      "stateMutability": "nonpayable",
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
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "psmRelativeDecimals",
          "type": "uint256"
        }
      ],
      "name": "setPSMSwapPairInfo",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        },
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token2",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token3",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        }
      ],
      "name": "setStableSwapFourPoolPairInfo",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        },
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        }
      ],
      "name": "setStableSwapPairInfo",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "uint256",
          "name": "index",
          "type": "uint256"
        },
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token2",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        }
      ],
      "name": "setStableSwapThreePoolPairInfo",
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
      "name": "stableSwapFourPoolPairInfo",
      "outputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token2",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token3",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        }
      ],
      "stateMutability": "view",
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
      "name": "stableSwapPairInfo",
      "outputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
          "type": "address"
        }
      ],
      "stateMutability": "view",
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
      "name": "stableSwapThreePoolPairInfo",
      "outputs": [
        {
          "internalType": "address",
          "name": "swapContract",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token0",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token1",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "token2",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "LPContract",
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


const infoImp = await tronWeb.contract(StableInfoABI,cfg.stableSwapInfo);
// flag = 0, htxsunswap

// await infoImp.setExactSwapPairInfo(cfg.HtxSunSwap,cfg.HTX,cfg.SUN).send();
// // flag = 1, psm

// await infoImp.setPSMSwapPairInfo(cfg.usdt20psmpool.psm,cfg.usdd20Token,cfg.usdtToken,cfg.usdtpsmpool.gemJoin,1e12).send();
// // flag = 2, usdd202pool
// await infoImp.setStableSwapPairInfo(2,cfg.usdd202Pool,cfg.usdd20Token,cfg.usdt20Token,cfg.usdd202Pool).send();

// // flag = 3, usdd2pool
// await infoImp.setStableSwapPairInfo(3,cfg.usdd2pool,cfg.usddToken,cfg.usdtToken,cfg.usdd2pool).send();
// // flag = 4, tusdusdt2pool
// await infoImp.setStableSwapPairInfo(4,cfg.tusdusdt2pool,cfg.tusdToken,cfg.usdtToken,cfg.tusdusdt2pool).send();
// // flag = 5, old3pool
// await infoImp.setStableSwapThreePoolPairInfo(5,cfg.old3pool,cfg.usdjToken,cfg.tusdToken,cfg.usdtToken,cfg.old3pool).send();
// // flag = 10, oldusdcpool
// await infoImp.setStableSwapFourPoolPairInfo(10,cfg.oldusdcpool,cfg.usdcToken,cfg.usdjToken,cfg.tusdToken,cfg.usdtToken,cfg.oldusdcpool).send();
// // flag = 11, usdc2pooltusdusdt
// await infoImp.setStableSwapThreePoolPairInfo(11,cfg.usdc2pooltusdusdt,cfg.usdcToken,cfg.tusdToken,cfg.usdtToken,cfg.usdc2pooltusdusdt).send();
// // flag = 12, usdd2pooltusdusdt
// await infoImp.setStableSwapThreePoolPairInfo(12,cfg.usdd2pooltusdusdt,cfg.usddToken,cfg.tusdToken,cfg.usdtToken,cfg.usdd2pooltusdusdt).send();
// // flag = 13, usdj2pooltusdusdt
// await infoImp.setStableSwapThreePoolPairInfo(13,cfg.usdj2pooltusdusdt,cfg.usdjToken,cfg.tusdToken,cfg.usdtToken,cfg.usdj2pooltusdusdt).send();


console.log("set pool info done");

const pair2 = await infoImp.getStableSwapPairInfo(2).call();

console.log("pair2:",tronWeb.address.fromHex(pair2.swapContract));
console.log("pair2 token0:", tronWeb.address.fromHex( pair2.token0));
console.log("pair2 token1:", tronWeb.address.fromHex( pair2.token1)); 

const pair3 = await infoImp.getStableSwapThreePoolPairInfo(5).call();

console.log("pair3:",tronWeb.address.fromHex(pair3.swapContract));
console.log("pair3 token0:",  tronWeb.address.fromHex( pair3.token0));
console.log("pair3 token1:", tronWeb.address.fromHex( pair3.token1));
console.log("pair3 token2:", tronWeb.address.fromHex( pair3.token2));
console.log("pair3 lp:",  tronWeb.address.fromHex( pair3.LPContract));
// console.log("pair3:",tronWeb.address.fromHex(pair3.swapContract),  
// const pair4 = await infoImp.getStableSwapFourPoolPairInfo(10).call();
// console.log("pair4:",tronWeb.address.fromHex(pair4.swapContract),tronWeb.address.fromHex( pair4.token0),tronWeb.address.fromHex( pair4.token1),tronWeb.address.fromHex( pair4.token2),tronWeb.address.fromHex( pair4.token3),tronWeb.address.fromHex( pair4.LPContract));

const pair11 = await infoImp.getStableSwapThreePoolPairInfo(11).call();

console.log("pair11:",tronWeb.address.fromHex(pair11.swapContract));
console.log("pair11 token0:",  tronWeb.address.fromHex( pair11.token0));
console.log("pair11 token1:", tronWeb.address.fromHex( pair11.token1));
console.log("pair11 token2:", tronWeb.address.fromHex( pair11.token2));
console.log("pair11 lp:",  tronWeb.address.fromHex( pair11.LPContract));

const pair1 = await infoImp.getPSMSwapPairInfo(cfg.usdd20Token,cfg.usdtToken).call();

console.log("psm pair:",tronWeb.address.fromHex(pair1.swapContract),tronWeb.address.fromHex(pair1.token0),tronWeb.address.fromHex(pair1.token1),tronWeb.address.fromHex(pair1.LPContract),pair1.psmRelativeDecimals);
