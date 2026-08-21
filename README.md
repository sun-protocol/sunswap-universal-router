# Sunswap Universal Router

Sunswap Universal Router is a unified routing smart contract for the SunSwap ecosystem, designed to efficiently route token swaps and liquidity across different pools and swap paths.

Supported pool list:
- SunSwap V4 Pools
- SunSwap V3 Pools
- SunSwap V2 Pools
- SunSwap V1 Pools
- SunSwap Curve Pools
- HTX-SUN Fixed rate pool

This repository contains the smart contracts, deployment scripts, and tests based on **Hardhat** and **Foundry**, with additional support for the **TRON** network.

---

## Features

- **Unified routing layer**: A single router interface that can aggregate multiple swap/pool/aggregator logics.
- **Multi-network support**:
  - EVM local development network (`localhost`)
  - TRON testnet (via `tronweb` and `tronSolc`)
- **Gas / resource efficiency**: Solidity compiler optimization enabled (`runs=999999`, `viaIR: true`).

---

## Deployments

| contract        | chain        | address                            |
| :-------------- | :----------- | :--------------------------------- |
| UniversalRouter | TRON Mainnet | TQqgNg13s2DjvXhW1ky4v6TsR8wZGvb7Y4 |
|                 | NILE Testnet | TLmHD2TJoGVEMkGiE1JzSwd6CEPa8jXumJ |

## Tech Stack

- **Hardhat 2.25.0** (configured via `@sun-protocol/sun-studio`)
  +- **Hardhat Toolbox** & **Hardhat Foundry plugin**
- **Foundry** (`forge test`)
- **TronWeb 6.x**
- **Solidity 0.8.26 / Vyper 0.2.8 & 0.3.10**

---

## Project Structure (Overview)

- `contracts/`: Core contracts and libraries.
- `deploy/`: Deployment scripts for EVM networks (following Hardhat Deploy conventions).
- `deployTron/`: Deployment scripts targeting TRON.
- `scripts/`: Helper scripts (e.g. `postinstall`).
- `test/`: Hardhat-based tests.

---

## Prerequisites

**Requirements:**

- Node.js >= 18 (recommended)
- npm / yarn / pnpm (examples below use npm)
- Foundry installed (optional, for `forge test`)

**Clone and install:**

```bash
git clone https://github.com/your-repo/sunswap-universal-router.git
cd sunswap-universal-router

# Install dependencies
npm install
```

After installation, the `postinstall` hook will automatically run `scripts/postinstall.sh` for basic initialization.

---

## Environment Variables

Create a `.env` file in the project root (not committed to Git) with at least:

```bash
PRIVATE_KEY=your_private_key_for_deployment
```

> **Notes**:
>
> - Use a test/development account only; **do not** use a production account with real funds.
> - The same `PRIVATE_KEY` is reused for the TRON network (see `networks.tron.accounts` in `hardhat.config.ts`).

---

## NPM Scripts

All scripts are defined under the `scripts` field in `package.json` and can be run via `npm run <script>`.

- **Local node**

  ```bash
  npm run start
  # Equivalent to: hardhat node
  ```

- **Compile contracts (EVM)**

  ```bash
  npm run compile
  # Equivalent to: hardhat compile --verbose --force
  ```

- **Compile contracts (TRON)**

  ```bash
  npm run compile-tron
  # Equivalent to: hardhat compile --network tron --verbose --force
  ```

- **Clean build artifacts**

  ```bash
  npm run clean
  # Equivalent to: hardhat clean && rm -rf lib/
  ```

- **Hardhat tests**

  ```bash
  npm test
  # or
  npm run test
  ```

- **Foundry tests (optional)**

  ```bash
  npm run init-foundry   # Initialize Foundry project structure (run once)
  npm run test-foundry   # Equivalent to: forge test -vvv
  ```

---

## Deployment

### 1. Deploy to local network (`localhost`)

Start a local Hardhat node in one terminal:

```bash
npm run start
```

Deploy contracts from another terminal:

```bash
npm run deploy
```

> `deploy` is equivalent to: `npx hardhat --network localhost deploy --tags lumi`

### 2. Deploy to TRON testnet

Make sure `PRIVATE_KEY` is set in `.env`, then run:

```bash
npm run deploy-tron
```

> This uses the scripts under `deployTron/` and compiles/deploys via `tronSolc`.

### 3. Deploy to other EVM testnets (example: Sepolia)

`hardhat.config.ts` already includes a commented-out example configuration for the `sepolia` network.  
To enable it:

1. Uncomment the `sepolia` network configuration in `hardhat.config.ts` and set a proper `url` and `accounts`.
2. Run:

   ```bash
   npm run deploy-sepolia
   ```

---

## Contributing & Development Guidelines

- Before committing, it is recommended to run:

  ```bash
  npm run compile
  npm test
  ```

- Add unit tests or Foundry tests for any new routing logic or contracts.
- Follow the existing style and configuration (Solidity 0.8.26 / viaIR / high optimization runs).

Contributions via Issues and Pull Requests are welcome.

---

## License

Unless otherwise specified, this project follows the open-source license used by the upstream repository (for example, MIT or a similar permissive license).  
Before using it in production, please review the upstream repository and related license terms.

---

## Community & Support

If you have questions about this project, find bugs, or would like to contribute, you can reach the team and community via:

- [Telegram](https://t.me/SunIO_Defi)
- [Twitter](https://twitter.com/defi_sunio)

Please follow official announcements from these channels for the latest information on deployments, upgrades, and security notices.
