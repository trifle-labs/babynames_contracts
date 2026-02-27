# BabyNameMarket Overview

## Architecture

BabyNameMarket is a prediction market contract for SSA (Social Security Administration) baby name rankings. Users bet on which name will achieve a specific rank in a given year.

### Core Concepts

- **Category**: A prediction question (e.g., "Which name will be #1 Girl in 2025?")
- **Pool**: A betting option within a category (e.g., "Olivia", "Emma")
- **Tokens**: Purchased via bonding curve; represent share of prize pool if pool wins

### User Flow

1. Categories are created with initial name options and a deadline
2. Users buy tokens in pools using ETH (bonding curve pricing)
3. After real-world data is available, the resolver declares the winning pool
4. Winners claim their proportional share of the prize pool (minus 10% rake)

### Contract Design

- **Ownable**: Owner manages resolver, treasury, pause
- **ReentrancyGuard**: Protects buy() and claim()
- **Pausable**: Emergency stop for all trading
- **Buy-only**: No selling until resolution (prevents manipulation)
- **Pool-full mechanism**: Prevents buying when redemption would be below purchase price
