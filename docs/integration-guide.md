# Integration Guide

## Installation

```bash
npm install @trifle-labs/babynames-contracts
```

## Usage

### JavaScript/TypeScript

```typescript
import { abi, getDeployment, CHAIN_IDS } from "@trifle-labs/babynames-contracts";
import { createPublicClient, http } from "viem";
import { base } from "viem/chains";

// Get deployment for Base
const deployment = getDeployment(CHAIN_IDS.base);

const client = createPublicClient({ chain: base, transport: http() });

// Read current price
const price = await client.readContract({
  address: deployment.address,
  abi,
  functionName: "getCurrentPrice",
  args: [1n], // poolId
});

// Simulate a buy
const result = await client.readContract({
  address: deployment.address,
  abi,
  functionName: "simulateBuy",
  args: [1n, parseEther("0.1")],
});
```

### Direct ABI Import

```typescript
import abi from "@trifle-labs/babynames-contracts/abi/BabyNameMarket.json";
```

### Deployment Addresses

```typescript
import { getDeployment, CHAIN_IDS } from "@trifle-labs/babynames-contracts";

const baseDeploy = getDeployment(CHAIN_IDS.base);
// { address: "0x...", resolver: "0x...", chainId: 8453, chainName: "base" }
```
