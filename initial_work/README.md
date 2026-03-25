# BabyNameMarket

A prediction market for SSA baby name rankings using asymptotic bonding curves with parimutuel resolution.

## Overview

BabyNameMarket allows users to bet on which baby names will top the Social Security Administration's annual rankings. The system combines two pricing mechanisms:

1. **Bonding Curve** (early phase): Early buyers get discounted prices, rewarding conviction and early participation
2. **Parimutuel** (late phase): As prices approach $1, the system behaves like traditional parimutuel betting

### Key Features

- **Asymptotic pricing**: Prices approach but never exceed $1
- **Self-balancing**: "Pool full" mechanism prevents buying when winners would lose money
- **Buy-only**: No selling until resolution (prevents manipulation)
- **10% house rake**: Taken from prize pool at resolution
- **User-created markets**: Anyone can add names or create new categories

## Price Curve

The price function is:

```
P(S) = $1 × (1 - e^(-S/K))
```

Where:
- `S` = token supply
- `K` = 50,000 (curve softness parameter)
- At S=0: Price = $0
- At S=50,000: Price ≈ $0.63
- At S=150,000: Price ≈ $0.95
- At S=∞: Price → $1.00

### Price vs Collateral Table (K=50,000)

| Pool Collateral | Token Supply | Price |
|-----------------|--------------|-------|
| $5,000 | ~5,100 | $0.10 |
| $10,000 | ~11,000 | $0.20 |
| $25,000 | ~32,000 | $0.47 |
| $50,000 | ~74,000 | $0.77 |
| $100,000 | ~180,000 | $0.97 |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      BabyNameMarket                         │
├─────────────────────────────────────────────────────────────┤
│  Categories                                                 │
│  ├── Year (2025, 2026, ...)                                │
│  ├── Position (1-1000)                                      │
│  ├── Gender (Male/Female)                                   │
│  ├── Deadline                                               │
│  └── Pools[]                                                │
│       ├── Name ("Olivia", "Emma", ...)                     │
│       ├── Total Supply (tokens minted)                      │
│       └── Collateral (ETH collected)                        │
├─────────────────────────────────────────────────────────────┤
│  User Balances: poolId → address → tokenBalance             │
├─────────────────────────────────────────────────────────────┤
│  Treasury: Accumulated house rake                           │
└─────────────────────────────────────────────────────────────┘
```

## User Flow

### 1. Browse Categories
```solidity
// Get category info
(year, position, gender, totalCollateral, poolCount, resolved, ...) = 
    market.getCategoryInfo(categoryId);

// Get all pools in category
uint256[] memory poolIds = market.getCategoryPools(categoryId);

// Get pool details
(categoryId, name, totalSupply, collateral, currentPrice) = 
    market.getPoolInfo(poolId);
```

### 2. Check Pool Status
```solidity
// Can I buy?
(bool canBuy, string memory reason) = market.canBuy(poolId);

// Simulate my purchase
(tokens, avgPrice, expectedRedemption, profitIfWins) = 
    market.simulateBuy(poolId, 0.5 ether);
```

### 3. Place Bet
```solidity
// Buy tokens in a pool
market.buy{value: 0.5 ether}(poolId);
```

### 4. Wait for Resolution
```solidity
// Check if resolved
(,,,,, resolved, winningPoolId, prizePool,) = market.getCategoryInfo(categoryId);
```

### 5. Claim Winnings
```solidity
// If you bet on the winner
market.claim(winningPoolId);
```

## Pool Full Mechanism

When a pool becomes "oversubscribed" (expected redemption < current price), buying is blocked:

```
Example:
- Olivia pool: 100,000 tokens, $50,000 collateral
- Emma pool: 1,000 tokens, $500 collateral
- Total collateral: $50,500
- Prize pool (after 10% rake): $45,450

Expected Olivia redemption: $45,450 / 100,000 = $0.4545
Current Olivia price: ~$0.86

$0.4545 < $0.86 → POOL FULL

Users must bet on Emma/others to rebalance
```

This prevents the "winner loses" problem where late buyers could lose money even when correct.

## Resolution

1. SSA releases annual data (typically May)
2. Resolver (admin) calls `resolve(categoryId, winningPoolId)`
3. 10% rake transferred to treasury
4. Winners call `claim(poolId)` to receive their share of prize pool

### Payout Calculation

```
userPayout = (userTokens / totalWinningTokens) × prizePool
```

## Constants

| Parameter | Value | Description |
|-----------|-------|-------------|
| CEILING | $1.00 | Maximum token price |
| K | 50,000 | Curve softness (~$100k to reach $0.95) |
| HOUSE_RAKE_BPS | 1000 | 10% rake from prize pool |
| MIN_CATEGORY_COLLATERAL | 0.1 ETH | Threshold before pool-full kicks in |
| MIN_BET | 0.001 ETH | Minimum bet amount |

## Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
```

### Deploy

```bash
# Set environment variables
export PRIVATE_KEY=your_deployer_private_key
export RESOLVER_ADDRESS=your_resolver_address
export RPC_URL=https://base-mainnet.g.alchemy.com/v2/your-key

# Deploy
forge script script/Deploy.s.sol:DeployBabyNameMarket \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify

# Setup initial categories
export MARKET_ADDRESS=deployed_contract_address
forge script script/Deploy.s.sol:SetupInitialCategories \
    --rpc-url $RPC_URL \
    --broadcast
```

### Verify

```bash
forge verify-contract $MARKET_ADDRESS BabyNameMarket \
    --chain base \
    --constructor-args $(cast abi-encode "constructor(address)" $RESOLVER_ADDRESS)
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_FullFlow -vvv

# Gas report
forge test --gas-report
```

## Security Considerations

1. **Resolver Trust**: The resolver can determine winners. Use a multisig or eventually integrate ZK verification.

2. **No Selling**: Intentional design to prevent manipulation. Tokens are locked until resolution.

3. **Deadline Enforcement**: Betting closes before SSA data release to prevent information asymmetry.

4. **Reentrancy Protection**: All external calls are protected by `nonReentrant` modifier.

5. **Pausable**: Owner can pause in emergencies.

## Gas Estimates

| Operation | Gas (approx) |
|-----------|--------------|
| createCategory (10 names) | ~500,000 |
| buy | ~80,000 |
| resolve | ~60,000 |
| claim | ~50,000 |

On Base L2 at 0.001 gwei, costs are negligible (<$0.01 per operation).

## Future Improvements

1. **ZK Resolution**: Replace trusted resolver with SP1 proof of SSA data
2. **Secondary Market**: Allow token transfers/sales after deadline
3. **Exotic Bets**: Exacta (top 2 in order), Trifecta (top 3)
4. **Dynamic K**: Adjust curve based on market activity
5. **Referral Program**: Reward users who bring volume

## License

MIT
