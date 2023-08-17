import { HardhatUserConfig } from "hardhat/config";
import "@matterlabs/hardhat-zksync-toolbox";


import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  zksolc: {
    version: "latest",
    settings: {
      isSystem: true,
    },
  },
  defaultNetwork: "zkSyncTestnet",
  networks: {
    zkSyncTestnet: {
      url: "https://testnet.era.zksync.dev",
      ethNetwork: "https://rpc.ankr.com/eth_goerli",
      zksync: true,
      verifyURL: "https://zksync2-testnet-explorer.zksync.dev/contract_verification",
    },
    hardhat: {
      forking: {
        url: "https://testnet.era.zksync.dev",
      },
    },
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
