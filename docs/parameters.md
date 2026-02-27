# Contract Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `CEILING` | 1e18 (1 ETH) | Maximum token price; provides natural upper bound |
| `K` | 50,000e18 | Curve softness; hot pools approach $1 at ~$100k volume |
| `HOUSE_RAKE_BPS` | 1000 (10%) | Revenue rate; balances protocol sustainability and user returns |
| `MIN_CATEGORY_COLLATERAL` | 0.1 ETH | Threshold before pool-full checks activate |
| `MIN_BET` | 0.001 ETH | Minimum transaction; prevents dust spam |
| `POOL_FULL_BUFFER_BPS` | 9500 (95%) | Pool-full threshold; 5% buffer prevents marginal rejections |

## Sensitivity Analysis

- **K too low** (e.g., 1,000): Prices hit ceiling quickly, early buyers dominate
- **K too high** (e.g., 1,000,000): Prices stay near zero, poor price discovery
- **HOUSE_RAKE_BPS too high**: Winners get poor returns, reduces participation
- **HOUSE_RAKE_BPS too low**: Protocol not sustainable
- **POOL_FULL_BUFFER_BPS too tight** (99%): Pools lock too early
- **POOL_FULL_BUFFER_BPS too loose** (80%): Buyers risk guaranteed losses
