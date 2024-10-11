require("dotenv").config();

module.exports = {
  solidity: "0.8.23",
  networks: {
    hardhat: {
      forking: {
        url: process.env.MAINNET_RPC_URL,
      },
      chainId: 1337,
    },
  },
};