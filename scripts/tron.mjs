import { TronWeb } from 'tronweb';

let tronWeb = null;

export async function initTronWeb(config) {

  if (tronWeb == null) {
    tronWeb = new TronWeb(
      'https://nile.trongrid.io',
      'https://nile.trongrid.io',
      'https://nile.trongrid.io',
      process.env.PRIVATE_KEY
    );
  }
  return tronWeb;
}


