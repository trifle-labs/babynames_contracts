# BabyNameMarket

A prediction market for SSA baby name rankings, built with Foundry.

Users bet on which baby names will top the Social Security Administration's annual rankings. The contract combines bonding curve pricing with parimutuel resolution — early conviction is rewarded with cheaper tokens, and winners split the prize pool proportionally.

## How It Works

```
1. Categories are created   →  "Which name will be #1 Girl in 2025?"
2. Users buy tokens          →  Pick a name, pay USDC (ERC20), get tokens via bonding curve
3. Resolver declares winner  →  SSA data comes out, winning pool is set
4. Winners claim payouts     →  Pro-rata share of 90% of total collateral
```

### Category Types

| Type | Constant | Description |
|------|----------|-------------|
| Single | `CAT_SINGLE` (0) | Predict the name at one specific rank |
| Exacta | `CAT_EXACTA` (1) | Predict names at two specific ranks (ordered) |
| Trifecta | `CAT_TRIFECTA` (2) | Predict names at three specific ranks (ordered) |
| Top-N | `CAT_TOP_N` (3) | Predict names that appear anywhere in the top N |

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
| `CEILING` | 1.00 USDC | Maximum token price |
| `K` | 50,000 | Curve softness |
| `HOUSE_RAKE_BPS` | 1000 | 10% rake from prize pool |
| `MIN_CATEGORY_COLLATERAL` | 0.1 USDC | Minimum category collateral before pool-full cap |
| `MIN_BET` | 0.001 USDC | Minimum bet amount |

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
(year, position, categoryType, gender, totalCollateral, poolCount, resolved, winningPoolId, prizePool, deadline)
    = market.getCategoryInfo(categoryId);

uint256[] memory poolIds = market.getCategoryPools(categoryId);
(categoryId, name, totalSupply, collateral, currentPrice) = market.getPoolInfo(poolId);

// Simulate before buying (amount in token's native decimals, e.g. 1_000_000 for 1 USDC)
(tokens, avgPrice, expectedRedemption, profitIfWins) = market.simulateBuy(poolId, 1_000_000);

// Approve and buy tokens
collateralToken.approve(address(market), 1_000_000);
market.buy(poolId, 1_000_000);
```

### Add a Name and Buy in One Step

```solidity
// Create a pool for a name and immediately buy tokens
collateralToken.approve(address(market), 1_000_000);
market.addNameAndBuy(categoryId, "Olivia", merkleProof, 1_000_000);
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
# Set PRIVATE_KEY, RESOLVER_ADDRESS, TOKEN_ADDRESS (e.g. USDC address), and RPC URLs

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
forge test               # Run 123 tests (unit, integration, fuzz, edge)
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
├── unit/          8 files — category creation, buying, resolution, admin, curve math, views, merkle whitelist, top-N resolution
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
├── DeployTestnet.s.sol             Testnet deployment with mock token setup
├── SetupCategories.s.sol           Creates initial girl + boy name categories
├── SeedCategories.s.sol            Seed categories with names
├── SeedTopN.s.sol                  Seed top-N categories
├── SeedTrifecta.s.sol              Seed trifecta categories
├── SeedExactaTrifecta.s.sol        Seed exacta/trifecta combined categories
├── SeedExpanded.s.sol              Expanded name seeding
├── SeedLight.s.sol                 Lightweight category seeding
├── SetMerkleRoot.s.sol             Update the names Merkle root on-chain
└── helpers/ChainConfig.sol         Per-chain resolver and deadline config
```

## Security

- **ReentrancyGuard** on `buy()` and `claim()`
- **Pausable** emergency stop
- **Buy-only** until resolution (no selling prevents manipulation)
- **Pool-full mechanism** prevents guaranteed-loss purchases
- **Merkle name whitelist** restricts pools to SSA-verified names (configurable; names can also be manually approved by owner)
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
