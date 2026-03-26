# Trifle Prediction Markets

LMSR prediction markets for SSA baby name rankings, built with Foundry.

Markets are bootstrapped through a commitment-based Vault — users propose names, commit capital, and once a threshold is met the market launches with all participants getting the same fair price. After launch, anyone can trade freely on the LMSR automated market maker.

## Contracts

| Contract | Description |
|----------|-------------|
| `PredictionMarket.sol` | LS-LMSR market with derived liquidity depth, admin-settable creation fee |
| `Vault.sol` | Commitment-based market bootstrapping with Merkle name validation, year/region scoping |
| `OutcomeToken.sol` | ERC20 outcome tokens (6 decimals, clone-deployed per market) |
| `RewardDistributor.sol` | Merkle-based USDC reward distribution |

Based on [Context Markets](https://github.com/contextwtf/contracts) contracts, used under license.

## How It Works

```
1. Admin opens a year         →  openYear(2025)
2. User proposes a name       →  propose("olivia", 2025, proof, [5e6, 0])
3. Others commit capital      →  commit(proposalId, [10e6, 0])
4. Threshold met, anyone      →  launchMarket(proposalId)
   triggers launch
5. Users claim tokens         →  claimShares(proposalId) → tokens to wallet
6. Anyone trades freely       →  predictionMarket.trade(...)
7. Oracle resolves            →  resolveMarketWithPayoutSplit(marketId, payouts)
8. Token holders redeem       →  predictionMarket.redeem(token, amount)
```

### Market Scoping

Each market is scoped to **(name, year, region)**:
- `propose("olivia", 2025, ...)` — national ranking
- `proposeRegional("olivia", 2025, "CA", ...)` — California state ranking

Regions use two-letter US state abbreviations. All 50 states are prepopulated. Admin can add more via `addRegion()`.

### Year Lifecycle

Years are **locked by default**. Admin controls the lifecycle:
- `openYear(2025)` — proposals can be created for 2025
- `closeYear(2025)` — no new 2025 proposals, existing markets continue trading
- Resolution happens when SSA data is published (typically after Mother's Day)

### Pricing (LS-LMSR)

Markets use Liquidity-Sensitive LMSR (Othman et al. 2013):
- Initial prices: 50/50 for binary markets
- Market depth scales with the creation fee
- At $5/outcome: moving YES from 50¢ to 90¢ costs ~$27
- Target vig: 7% on balanced volume

| Parameter | Default | Description |
|-----------|---------|-------------|
| `marketCreationFee` | $5/outcome | Total fee = fee × outcomes |
| `targetVig` | 7% | Expected spread on balanced volume |
| `defaultLaunchThreshold` | $20 | Min commitment to trigger launch |

## Deployments

### Base Sepolia (84532)

| Contract | Address |
|----------|---------|
| PredictionMarket | `0xc169111687F20868C098670B339F4cC18e01b750` |
| Vault | `0xCE18752dB06aEAF33563E23d7fEc1C0d3A4A8BAF` |
| TestUSDC | `0x24495a2F5FCc4494B247a511c91104e6cF50AD13` |
| RewardDistributor | `0xfA2DD21172aD0d8e24aE37D8d9345B7854b2c2ab` |

### Tempo Moderato (42431)

| Contract | Address |
|----------|---------|
| PredictionMarket | `0x623F553D0E77CE1F44EB39E39AB4cBd4C3874cF3` |
| Vault | `0x06C609eA9A0c9dA84f3AF277e96E604635441235` |
| TestUSDC | `0x6c60a69d197c333a012E160be83E18d0C70B25b5` |
| RewardDistributor | `0x7406E3B5A1158aac919615cC7D5c2fc5B14Dfc82` |

## Quick Start

```bash
git clone --recurse-submodules https://github.com/trifle-labs/babynames_contracts
cd babynames_contracts
forge build
forge test
```

## npm Package

```bash
npm install @trifle-labs/babynames-contracts
```

```javascript
const {
  PredictionMarketABI,
  VaultABI,
  OutcomeTokenABI,
  getDeployment,
  CHAIN_IDS,
} = require("@trifle-labs/babynames-contracts");

const deploy = getDeployment(CHAIN_IDS.baseSepolia);
// deploy.PredictionMarket, deploy.Vault, deploy.TestUSDC, ...
```

## Development

```bash
forge build              # Compile
forge test -vv           # Run 80 tests
make export-abi          # Export ABIs to abi/
make deploy-base-sepolia # Deploy to Base Sepolia
make deploy-tempo-testnet # Deploy to Tempo testnet
```

### Test Structure

```
test/
├── PredictionMarket.t.sol      31 tests — creation, trading, resolution, solvency, admin, multi-outcome
├── PredictionMarketFuzz.t.sol   8 tests — solvency fuzz (512 runs), fee invariant fuzz, round-trip bounds
├── Vault.t.sol                 28 tests — propose, commit, launch, claims, withdraw, year/region scoping
└── VaultEdge.t.sol             13 tests — dust accounting, tiny commits, binary search edge cases
```

### Architecture

```
src/
├── PredictionMarket.sol     LS-LMSR market maker (OwnableRoles)
├── Vault.sol                Commitment bootstrapping + name/year/region validation
├── OutcomeToken.sol         ERC20 clone per outcome (6 decimals)
└── RewardDistributor.sol    Merkle epoch rewards

src/archive/                 Previous BabyNameMarket contracts (archived)
initial_work/                Previous scripts and tests (archived)
```

## License

BUSL-1.1 (source contracts), MIT (tests and scripts)
