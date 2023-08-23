import { HardhatUserConfig } from "hardhat/config";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-verify";

import "dotenv/config";

const zkSyncTestnet =
  process.env.NODE_ENV == "test"
    ? {
        url: "http://0.0.0.0:8011",
        ethNetwork: "http://localhost:8545",
        zksync: true,
      }
    : {
        url: "https://zksync2-testnet.zksync.dev",
        ethNetwork: "https://rpc.ankr.com/eth_goerli",
        zksync: true,
        verifyURL:
          "https://zksync2-testnet-explorer.zksync.dev/contract_verification",
      };

const config: HardhatUserConfig = {
  zksolc: {
    version: "latest",
    settings: {
      isSystem: true,
    },
  },
  defaultNetwork: "zkSyncTestnet",
  networks: {
    hardhat: {
      zksync: true,
    },
    zkSyncTestnet,
    zkSync: {
      url: "https://mainnet.era.zksync.io",
      ethNetwork: "https://rpc.ankr.com/eth",
      zksync: true,
      verifyURL:
        "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
  },
  solidity: {
    version: "0.8.17",
  },
  mocha: {
    timeout: 100000000,
  },
};

export default config;
