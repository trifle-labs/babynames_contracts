# Chain Configurations

| Chain | Chain ID | Explorer | RPC Notes |
|-------|----------|----------|-----------|
| ETH Mainnet | 1 | etherscan.io | Standard Ethereum RPC |
| Sepolia | 11155111 | sepolia.etherscan.io | Ethereum testnet |
| Base | 8453 | basescan.org | L2, low gas (~$0.01) |
| Base Sepolia | 84532 | sepolia.basescan.org | Base testnet |

## Gas Notes

- **Mainnet**: ~$5-50 per transaction depending on congestion
- **Sepolia**: Free (testnet ETH from faucets)
- **Base**: ~$0.01-0.10 per transaction (L2 efficiency)
- **Base Sepolia**: Free (testnet ETH from Base faucet)

## Etherscan V2 Verification

All chains use the unified Etherscan API key. Base chains require explicit API URLs:
- Base: `https://api.basescan.org/api`
- Base Sepolia: `https://api-sepolia.basescan.org/api`
