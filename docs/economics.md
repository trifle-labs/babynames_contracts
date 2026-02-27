# Economics

## Bonding Curve

Price function: `P(S) = CEILING * (1 - e^(-S/K))`

- **S**: Total token supply in pool
- **K**: Softness parameter (50,000 tokens) - controls how fast price rises
- **CEILING**: Maximum price ($1.00)

As supply grows, price asymptotically approaches $1. Early buyers get cheaper tokens.

## Cost Calculation

Cost to buy N tokens from supply S:
```
Cost = CEILING * [N - K * (e^(-(S+N)/K) - e^(-S/K))]
```

This is the integral of the price function from S to S+N.

## Parimutuel Resolution

When a category resolves:
1. 10% rake is taken from total collateral
2. Remaining 90% becomes the prize pool
3. Prize pool is distributed proportionally to winning pool token holders

```
Payout = (userTokens / winningPoolSupply) * prizePool
```

## Pool-Full Mechanism

Prevents buying when projected redemption falls below 95% of current price:

```
projectedRedemption = (totalCollateral * 0.9) / winningPoolSupply
Must satisfy: projectedRedemption >= currentPrice * 0.95
```

This protects buyers from guaranteed losses.
