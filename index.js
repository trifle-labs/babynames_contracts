const fs = require("fs");
const path = require("path");

const abi = require("./abi/BabyNameMarket.json");

function getDeployment(chainId) {
  const filePath = path.join(__dirname, "deployments", `${chainId}.json`);
  if (!fs.existsSync(filePath)) return null;
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

const CHAIN_IDS = {
  mainnet: 1,
  sepolia: 11155111,
  base: 8453,
  baseSepolia: 84532,
};

module.exports = { abi, getDeployment, CHAIN_IDS };
