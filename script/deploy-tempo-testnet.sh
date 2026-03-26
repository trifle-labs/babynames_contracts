#!/bin/bash
# Deploy prediction market contracts to Tempo testnet (Moderato)
# Uses forge create + cast send for RPC-based gas estimation (required for Tempo)
set -e

source .env
RPC="https://rpc.moderato.tempo.xyz"
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
echo "Deployer: $DEPLOYER"
echo "Chain: Tempo Moderato (42431)"

# 1. Deploy TestUSDC
echo "--- Deploying TestUSDC ---"
USDC_RESULT=$(forge create script/DeployTestnet.s.sol:TestUSDC \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy --broadcast --json)
USDC=$(echo $USDC_RESULT | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "TestUSDC: $USDC"

# 2. Mint 10M tUSDC to deployer
echo "--- Minting 10M tUSDC ---"
cast send $USDC "mint(address,uint256)" $DEPLOYER 10000000000000 \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

# 3. Deploy PredictionMarket
echo "--- Deploying PredictionMarket ---"
PM_RESULT=$(forge create src/PredictionMarket.sol:PredictionMarket \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy --broadcast --json)
PM=$(echo $PM_RESULT | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "PredictionMarket: $PM"

# 4. Initialize PredictionMarket
echo "--- Initializing PredictionMarket ---"
cast send $PM "initialize(address)" $USDC \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

# 5. Grant PROTOCOL_MANAGER_ROLE to deployer and set fee
echo "--- Granting PROTOCOL_MANAGER_ROLE ---"
cast send $PM "grantRoles(address,uint256)" $DEPLOYER 1 \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

echo "--- Setting marketCreationFee to \$5 ---"
cast send $PM "setMarketCreationFee(uint256)" 5000000 \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

# 6. Deploy Vault (predictionMarket, surplusRecipient, defaultOracle, defaultLaunchThreshold, defaultDeadlineDuration, owner)
echo "--- Deploying Vault ---"
VAULT_RESULT=$(forge create src/Vault.sol:Vault \
  --constructor-args "$PM" "$DEPLOYER" "$DEPLOYER" "20000000" "604800" "$DEPLOYER" \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy --broadcast --json)
VAULT=$(echo $VAULT_RESULT | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "Vault: $VAULT"

# 7. Grant MARKET_CREATOR_ROLE to Vault on PredictionMarket
echo "--- Granting MARKET_CREATOR_ROLE to Vault ---"
cast send $PM "grantMarketCreatorRole(address)" $VAULT \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

# 8. Fund Vault with tUSDC for market creation fees
echo "--- Funding Vault with 100 tUSDC ---"
cast send $USDC "mint(address,uint256)" $VAULT 100000000 \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy

# 9. Deploy RewardDistributor
echo "--- Deploying RewardDistributor ---"
RD_RESULT=$(forge create src/RewardDistributor.sol:RewardDistributor \
  --constructor-args $USDC $DEPLOYER \
  --rpc-url $RPC --private-key $PRIVATE_KEY --legacy --broadcast --json)
RD=$(echo $RD_RESULT | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "RewardDistributor: $RD"

# Get OutcomeToken implementation address
OT_IMPL=$(cast call $PM "outcomeTokenImplementation()(address)" --rpc-url $RPC)

# Write deployment artifact
echo "--- Writing deployment artifact ---"
cat > deployments/42431.json << EOF
{"PredictionMarket":"$PM","Vault":"$VAULT","TestUSDC":"$USDC","RewardDistributor":"$RD","OutcomeTokenImpl":"$OT_IMPL","chainId":42431,"deployer":"$DEPLOYER","oracle":"$DEPLOYER","surplusRecipient":"$DEPLOYER"}
EOF

echo ""
echo "=== Deployment Complete ==="
echo "TestUSDC:          $USDC"
echo "PredictionMarket:  $PM"
echo "Vault:             $VAULT"
echo "RewardDistributor: $RD"
echo "OutcomeToken impl: $OT_IMPL"
