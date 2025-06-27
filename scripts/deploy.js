// Enhanced deployment script
const CONTRACT_NAME = 'public-transport-token';
const NETWORK = 'testnet';

const config = {
  contractName: CONTRACT_NAME,
  network: NETWORK,
  governanceFeatures: true,
  enhancedVoting: true
};

console.log(`Deploying enhanced ${CONTRACT_NAME} to ${NETWORK}...`);
module.exports = config;
