# BabyNameMarket

A prediction market for SSA baby name rankings, built with Foundry.

Users bet on which baby names will top the Social Security Administration's annual rankings. The contract combines bonding curve pricing with parimutuel resolution — early conviction is rewarded with cheaper tokens, and winners split the prize pool proportionally.

## How It Works

```
1. Categories are created   →  "Which name will be #1 Girl in 2025?"
2. Users buy tokens          →  Pick a name, pay ETH, get tokens via bonding curve
3. Resolver declares winner  →  SSA data comes out, winning pool is set
4. Winners claim payouts     →  Pro-rata share of 90% of total collateral
```

### Price Curve

```
P(S) = $1 × (1 - e^(-S/K))     K = 50,000
```

| Pool Volume | Token Price |
|-------------|-------------|
| $5,000      | ~$0.10      |
| $25,000     | ~$0.47      |
| $50,000     | ~$0.77      |
| $100,000    | ~$0.97      |

Prices start near zero and asymptotically approach $1. A "pool full" mechanism prevents buying when projected redemption drops below the purchase price.

### Constants

| Parameter | Value | Description |
|-----------|-------|-------------|
| `CEILING` | $1.00 | Maximum token price |
| `K` | 50,000 | Curve softness |
| `HOUSE_RAKE_BPS` | 1000 | 10% rake from prize pool |
| `MIN_BET` | 0.001 ETH | Minimum bet |

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone
git clone --recurse-submodules https://github.com/trifle-labs/babynames_contracts
cd babynames_contracts

# Build & test
forge build
forge test
```

## Usage

### Browse & Bet

```solidity
// Check available pools
(year, position, gender, totalCollateral, poolCount, resolved, , , deadline)
    = market.getCategoryInfo(categoryId);

uint256[] memory poolIds = market.getCategoryPools(categoryId);
(categoryId, name, totalSupply, collateral, currentPrice) = market.getPoolInfo(poolId);

// Simulate before buying
(tokens, avgPrice, expectedRedemption, profitIfWins) = market.simulateBuy(poolId, 0.5 ether);

// Buy tokens
market.buy{value: 0.5 ether}(poolId);
```

### Claim Winnings

```solidity
// After resolution
market.claim(winningPoolId);
```

## Deployment

```bash
# Copy and fill in environment variables
cp .env.example .env

# Deploy to Base Sepolia (testnet)
make deploy-base-sepolia

# Deploy to Base (production)
make deploy-base

# Setup initial categories
MARKET_ADDRESS=<address> forge script script/SetupCategories.s.sol:SetupCategories \
    --rpc-url $BASE_RPC_URL --broadcast
```

Supported chains: ETH Mainnet, Sepolia, Base, Base Sepolia. All deployments auto-verify on Etherscan.

## Development

```bash
forge build              # Compile
forge test               # Run 91 tests (unit, integration, fuzz, edge)
forge test -vvv          # Verbose output
forge coverage           # Coverage report (>88% branch coverage on src/)
forge snapshot           # Gas snapshot
make export-abi          # Export ABI to abi/
anvil                    # Local devnet
make deploy-local        # Deploy to local anvil
```

### Test Structure

```
test/
├── unit/          6 files — category creation, buying, resolution, admin, curve math, views
├── integration/   2 files — full flow, multi-category
├── fuzz/          3 files — randomized buy amounts, math invariants, resolution payouts
├── edge/          3 files — pool-full boundary, overflow, reentrancy attack
└── helpers/       TestHelpers.sol — shared setup
```

## npm Package

```bash
npm install @trifle-labs/babynames-contracts
```

```typescript
import { abi, getDeployment, CHAIN_IDS } from "@trifle-labs/babynames-contracts";

const deployment = getDeployment(CHAIN_IDS.base);
// { address: "0x...", resolver: "0x...", chainId: 8453, chainName: "base" }
```

## Architecture

```
src/
├── BabyNameMarket.sol              Main contract (Ownable, ReentrancyGuard, Pausable)
└── interfaces/IBabyNameMarket.sol  Interface for integrators

script/
├── Deploy.s.sol                    Deployment script (writes deployments/<chainId>.json)
├── SetupCategories.s.sol           Creates initial girl + boy name categories
└── helpers/ChainConfig.sol         Per-chain resolver and deadline config
```

## Security

- **ReentrancyGuard** on `buy()` and `claim()`
- **Pausable** emergency stop
- **Buy-only** until resolution (no selling prevents manipulation)
- **Pool-full mechanism** prevents guaranteed-loss purchases
- **Resolver trust**: currently a trusted address; future work includes ZK verification of SSA data

## Docs

See [`docs/`](docs/) for detailed documentation:
- [Overview](docs/overview.md) — architecture and user flow
- [Economics](docs/economics.md) — bonding curve math and parimutuel resolution
- [Parameters](docs/parameters.md) — constants with rationale
- [Deployment](docs/deployment.md) — step-by-step deploy playbook
- [Chain Configs](docs/chain-configs.md) — supported chains and gas notes
- [Integration Guide](docs/integration-guide.md) — npm usage and TypeScript examples

## License

MIT
