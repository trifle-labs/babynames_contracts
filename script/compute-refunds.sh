#!/usr/bin/env bash
set -euo pipefail

# Compute refund calldata for bets placed after SSA publication time.
#
# Usage:
#   ./script/compute-refunds.sh \
#     --rpc <rpc-url> \
#     --market <market-address> \
#     --category <category-id> \
#     --cutoff <unix-timestamp>
#
# Requires: cast (foundry), jq

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --rpc) RPC_URL="$2"; shift 2 ;;
    --market) MARKET="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --cutoff) CUTOFF="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${RPC_URL:-}" || -z "${MARKET:-}" || -z "${CATEGORY:-}" || -z "${CUTOFF:-}" ]]; then
  echo "Usage: ./script/compute-refunds.sh --rpc <url> --market <addr> --category <id> --cutoff <timestamp>"
  exit 1
fi

echo "Category: $CATEGORY"
echo "Market: $MARKET"
echo "Cutoff: $CUTOFF ($(date -r "$CUTOFF" 2>/dev/null || date -d "@$CUTOFF" 2>/dev/null || echo "unknown"))"

# Get category pools
POOLS_RAW=$(cast call "$MARKET" "getCategoryPools(uint256)(uint256[])" "$CATEGORY" --rpc-url "$RPC_URL")
# Parse pool IDs from output like [1, 2, 3]
POOLS=$(echo "$POOLS_RAW" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed '/^$/d')
POOL_COUNT=$(echo "$POOLS" | wc -l | tr -d ' ')
echo "Pools ($POOL_COUNT): $(echo $POOLS | tr '\n' ' ')"

# Event signature
EVENT_SIG="TokensPurchased(uint256,address,uint256,uint256,uint256)"
EVENT_TOPIC=$(cast sig-event "$EVENT_SIG")

# Fetch events for each pool and filter by cutoff timestamp
REFUND_DATA=""

for POOL_ID in $POOLS; do
  POOL_TOPIC=$(cast to-uint256 "$POOL_ID")

  # Get logs for this pool
  LOGS=$(cast logs \
    --from-block 0 \
    --to-block latest \
    --address "$MARKET" \
    --rpc-url "$RPC_URL" \
    "$EVENT_TOPIC" \
    "0x$POOL_TOPIC" \
    2>/dev/null || true)

  if [[ -z "$LOGS" ]]; then
    continue
  fi

  # Parse each log entry
  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Extract block number from log
    BLOCK_NUM=$(echo "$line" | jq -r '.blockNumber // empty' 2>/dev/null || true)
    [[ -z "$BLOCK_NUM" ]] && continue

    # Get block timestamp
    BLOCK_TS=$(cast block "$BLOCK_NUM" --rpc-url "$RPC_URL" -f timestamp 2>/dev/null || true)
    [[ -z "$BLOCK_TS" ]] && continue

    # Check if after cutoff
    if [[ "$BLOCK_TS" -gt "$CUTOFF" ]]; then
      # Decode event data
      TOPICS=$(echo "$line" | jq -r '.topics[]' 2>/dev/null)
      DATA=$(echo "$line" | jq -r '.data' 2>/dev/null)

      # Topic 1 = poolId (indexed), Topic 2 = buyer (indexed)
      BUYER_TOPIC=$(echo "$TOPICS" | sed -n '3p')
      BUYER="0x$(echo "$BUYER_TOPIC" | sed 's/0x//' | tail -c 41)"

      # Data contains: tokens (uint256), cost (uint256), avgPrice (uint256)
      TOKENS=$(echo "$DATA" | cut -c 3-66 | sed 's/^0*//' )
      COST=$(echo "$DATA" | cut -c 67-130 | sed 's/^0*//' )

      [[ -z "$TOKENS" ]] && TOKENS="0"
      [[ -z "$COST" ]] && COST="0"

      # Convert from hex
      TOKENS_DEC=$(printf "%d" "0x$TOKENS" 2>/dev/null || echo "0")
      COST_DEC=$(printf "%d" "0x$COST" 2>/dev/null || echo "0")

      echo "  REFUND: Pool $POOL_ID, Buyer $BUYER, Tokens $TOKENS_DEC, Cost $COST_DEC (block $BLOCK_NUM, ts $BLOCK_TS)"
      REFUND_DATA="$REFUND_DATA
$POOL_ID|$BUYER|$TOKENS_DEC|$COST_DEC"
    fi
  done < <(echo "$LOGS" | jq -c '.' 2>/dev/null || true)
done

# Remove leading newline
REFUND_DATA=$(echo "$REFUND_DATA" | sed '/^$/d')

if [[ -z "$REFUND_DATA" ]]; then
  echo ""
  echo "No refunds needed — no bets found after cutoff."
  exit 0
fi

# Aggregate by (poolId, user)
echo ""
echo "--- Aggregating refunds ---"
declare -A TOKEN_MAP
declare -A COLLATERAL_MAP
KEYS=""

while IFS='|' read -r pid user tokens collateral; do
  KEY="${pid}|${user}"
  EXISTING_T=${TOKEN_MAP[$KEY]:-0}
  EXISTING_C=${COLLATERAL_MAP[$KEY]:-0}
  TOKEN_MAP[$KEY]=$((EXISTING_T + tokens))
  COLLATERAL_MAP[$KEY]=$((EXISTING_C + collateral))
  if [[ ! " $KEYS " =~ " $KEY " ]]; then
    KEYS="$KEYS $KEY"
  fi
done <<< "$REFUND_DATA"

# Build arrays for the contract call
POOL_IDS_ARR=""
USERS_ARR=""
TOKEN_AMTS_ARR=""
COLLATERAL_AMTS_ARR=""
COUNT=0

for KEY in $KEYS; do
  IFS='|' read -r pid user <<< "$KEY"
  tokens=${TOKEN_MAP[$KEY]}
  collateral=${COLLATERAL_MAP[$KEY]}

  echo "  Pool $pid, User $user: $tokens tokens, $collateral collateral"

  POOL_IDS_ARR="${POOL_IDS_ARR:+$POOL_IDS_ARR,}$pid"
  USERS_ARR="${USERS_ARR:+$USERS_ARR,}$user"
  TOKEN_AMTS_ARR="${TOKEN_AMTS_ARR:+$TOKEN_AMTS_ARR,}$tokens"
  COLLATERAL_AMTS_ARR="${COLLATERAL_AMTS_ARR:+$COLLATERAL_AMTS_ARR,}$collateral"
  COUNT=$((COUNT + 1))
done

echo ""
echo "--- $COUNT refund entries ---"
echo ""
echo "To execute, run:"
echo ""
echo "cast send $MARKET \\"
echo "  'refundInvalidBets(uint256,uint256[],address[],uint256[],uint256[])' \\"
echo "  $CATEGORY '[$POOL_IDS_ARR]' '[$USERS_ARR]' '[$TOKEN_AMTS_ARR]' '[$COLLATERAL_AMTS_ARR]' \\"
echo "  --rpc-url $RPC_URL --private-key \$PRIVATE_KEY"
