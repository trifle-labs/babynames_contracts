# Deployment Playbook

## Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- `.env` file configured (see `.env.example`)
- Funded deployer wallet

## Per-Chain Deployment

### 1. Base Sepolia (Testnet)

```bash
# Deploy
make deploy-base-sepolia

# Verify (automatic with --verify flag)
# Setup initial categories
MARKET_ADDRESS=<deployed_address> forge script script/SetupCategories.s.sol:SetupCategories \
  --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast
```

### 2. Sepolia (Testnet)

```bash
make deploy-sepolia
```

### 3. Base (Production)

```bash
make deploy-base
```

### 4. ETH Mainnet (Production)

```bash
make deploy-mainnet
```

## Post-Deployment Checklist

1. Verify contract on block explorer
2. Run `SetupCategories` script
3. Export ABI: `make export-abi`
4. Update `deployments/<chainId>.json`
5. Test buy/resolve/claim flow on testnet
6. Set resolver address if different from deployer
