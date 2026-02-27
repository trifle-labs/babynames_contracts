// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BabyNameMarket
 * @notice Prediction market for SSA baby name rankings using asymptotic bonding curves
 * @dev Uses P(S) = CEILING * (1 - e^(-S/K)) with parimutuel resolution
 *
 * Key Features:
 * - Asymptotic curve approaching $1 max price
 * - Buy-only (no selling) until resolution
 * - "Pool full" mechanism prevents buying when winners would lose
 * - 10% house rake taken at resolution
 * - User-created categories and pools
 */
contract BabyNameMarket is Ownable, ReentrancyGuard, Pausable {

    // ============ Constants ============

    /// @notice Maximum token price (scaled by 1e18)
    uint256 public constant CEILING = 1e18; // $1.00

    /// @notice Curve softness parameter - higher = slower price growth
    /// @dev For $10MM target volume, K=50,000 means hot pools hit $1 at ~$100k
    uint256 public constant K = 50_000e18;

    /// @notice House rake in basis points (1000 = 10%)
    uint256 public constant HOUSE_RAKE_BPS = 1000;

    /// @notice Minimum category collateral before pool-full cap kicks in
    uint256 public constant MIN_CATEGORY_COLLATERAL = 0.1 ether;

    /// @notice Minimum bet amount
    uint256 public constant MIN_BET = 0.001 ether;

    /// @notice Precision for fixed-point math
    uint256 private constant PRECISION = 1e18;

    /// @notice Buffer for pool-full check (95% = can buy if redemption >= 95% of price)
    uint256 private constant POOL_FULL_BUFFER_BPS = 9500;

    // ============ Types ============

    enum Gender { Female, Male }

    struct Pool {
        uint256 categoryId;
        string name;
        uint256 totalSupply;    // Total tokens minted (scaled by 1e18)
        uint256 collateral;     // ETH collected into this pool
    }

    struct Category {
        uint256 year;
        uint256 position;       // Rank being predicted (1-1000)
        Gender gender;
        uint256[] poolIds;
        uint256 totalCollateral;
        bool resolved;
        uint256 winningPoolId;
        uint256 prizePool;      // Total collateral minus rake
        uint256 deadline;       // Betting closes at this timestamp
    }

    // ============ State ============

    uint256 public nextPoolId = 1;
    uint256 public nextCategoryId = 1;

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => Category) public categories;
    mapping(uint256 => mapping(address => uint256)) public balances;
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Accumulated house revenue
    uint256 public treasury;

    /// @notice Address authorized to resolve markets
    address public resolver;

    // ============ Events ============

    event CategoryCreated(
        uint256 indexed categoryId,
        uint256 year,
        uint256 position,
        Gender gender,
        uint256 deadline
    );

    event PoolCreated(
        uint256 indexed poolId,
        uint256 indexed categoryId,
        string name
    );

    event TokensPurchased(
        uint256 indexed poolId,
        address indexed buyer,
        uint256 tokens,
        uint256 cost,
        uint256 avgPrice
    );

    event CategoryResolved(
        uint256 indexed categoryId,
        uint256 winningPoolId,
        string winningName,
        uint256 totalCollateral,
        uint256 prizePool,
        uint256 rake
    );

    event WinningsClaimed(
        uint256 indexed poolId,
        address indexed claimer,
        uint256 tokens,
        uint256 payout
    );

    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event ResolverUpdated(address indexed oldResolver, address indexed newResolver);

    // ============ Errors ============

    error InvalidCategory();
    error InvalidPool();
    error CategoryAlreadyResolved();
    error CategoryNotResolved();
    error BettingClosed();
    error PoolOversubscribed();
    error InsufficientBet();
    error NotWinningPool();
    error AlreadyClaimed();
    error NoBalance();
    error NotResolver();
    error MinTwoOptions();
    error InvalidPosition();
    error InvalidDeadline();
    error TransferFailed();
    error PoolNotInCategory();

    // ============ Constructor ============

    constructor(address _resolver) Ownable(msg.sender) {
        resolver = _resolver;
    }

    // ============ Modifiers ============

    modifier onlyResolver() {
        if (msg.sender != resolver) revert NotResolver();
        _;
    }

    // ============ Admin Functions ============

    function setResolver(address _resolver) external onlyOwner {
        emit ResolverUpdated(resolver, _resolver);
        resolver = _resolver;
    }

    function withdrawTreasury(address to) external onlyOwner {
        uint256 amount = treasury;
        treasury = 0;

        (bool sent, ) = to.call{value: amount}("");
        if (!sent) revert TransferFailed();

        emit TreasuryWithdrawn(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Category Management ============

    /**
     * @notice Create a new prediction category with initial pools
     * @param year The year of SSA data (e.g., 2025)
     * @param position The rank being predicted (1-1000)
     * @param gender Male or Female
     * @param names Initial pool names (minimum 2)
     * @param deadline Timestamp when betting closes
     */
    function createCategory(
        uint256 year,
        uint256 position,
        Gender gender,
        string[] calldata names,
        uint256 deadline
    ) external whenNotPaused returns (uint256 categoryId) {
        if (names.length < 2) revert MinTwoOptions();
        if (position < 1 || position > 1000) revert InvalidPosition();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        categoryId = nextCategoryId++;

        Category storage cat = categories[categoryId];
        cat.year = year;
        cat.position = position;
        cat.gender = gender;
        cat.deadline = deadline;

        for (uint256 i = 0; i < names.length; i++) {
            _createPool(categoryId, names[i]);
        }

        emit CategoryCreated(categoryId, year, position, gender, deadline);
    }

    /**
     * @notice Add a new name option to an existing category
     * @param categoryId The category to add to
     * @param name The name to add as a betting option
     */
    function addNameToCategory(
        uint256 categoryId,
        string calldata name
    ) external whenNotPaused returns (uint256 poolId) {
        if (categoryId >= nextCategoryId) revert InvalidCategory();
        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();
        if (block.timestamp >= cat.deadline) revert BettingClosed();

        poolId = _createPool(categoryId, name);
    }

    function _createPool(
        uint256 categoryId,
        string memory name
    ) internal returns (uint256 poolId) {
        poolId = nextPoolId++;

        pools[poolId] = Pool({
            categoryId: categoryId,
            name: name,
            totalSupply: 0,
            collateral: 0
        });

        categories[categoryId].poolIds.push(poolId);

        emit PoolCreated(poolId, categoryId, name);
    }

    // ============ Trading ============

    /**
     * @notice Purchase tokens in a pool
     * @param poolId The pool to buy into
     * @dev Reverts if pool is oversubscribed (expected redemption < price)
     */
    function buy(uint256 poolId) external payable nonReentrant whenNotPaused {
        if (poolId >= nextPoolId) revert InvalidPool();
        if (msg.value < MIN_BET) revert InsufficientBet();

        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (cat.resolved) revert CategoryAlreadyResolved();
        if (block.timestamp >= cat.deadline) revert BettingClosed();

        // Check pool-full condition (only after minimum threshold)
        if (cat.totalCollateral >= MIN_CATEGORY_COLLATERAL) {
            if (!_canBuy(poolId, msg.value)) revert PoolOversubscribed();
        }

        // Calculate tokens for ETH amount
        uint256 tokens = _calculateTokensForEth(pool.totalSupply, msg.value);
        if (tokens == 0) revert InsufficientBet();

        uint256 avgPrice = msg.value * PRECISION / tokens;

        // Update state
        pool.totalSupply += tokens;
        pool.collateral += msg.value;
        cat.totalCollateral += msg.value;
        balances[poolId][msg.sender] += tokens;

        emit TokensPurchased(poolId, msg.sender, tokens, msg.value, avgPrice);
    }

    /**
     * @notice Check if a pool can accept more bets
     * @param poolId The pool to check
     * @param additionalBet The amount being added (for simulation)
     */
    function _canBuy(uint256 poolId, uint256 additionalBet) internal view returns (bool) {
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (pool.totalSupply == 0) return true; // Empty pools always open

        uint256 currentPrice = _getPrice(pool.totalSupply);

        // Simulate: what would redemption be after this purchase?
        uint256 newTokens = _calculateTokensForEth(pool.totalSupply, additionalBet);
        uint256 newTotalCollateral = cat.totalCollateral + additionalBet;
        uint256 newPoolSupply = pool.totalSupply + newTokens;

        // Prize pool after rake
        uint256 projectedPrizePool = newTotalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
        uint256 projectedRedemption = projectedPrizePool * PRECISION / newPoolSupply;

        // Allow if redemption >= 95% of current price
        return projectedRedemption >= currentPrice * POOL_FULL_BUFFER_BPS / 10000;
    }

    // ============ Resolution ============

    /**
     * @notice Resolve a category with the winning name
     * @param categoryId The category to resolve
     * @param winningPoolId The pool that won
     */
    function resolve(
        uint256 categoryId,
        uint256 winningPoolId
    ) external onlyResolver {
        if (categoryId >= nextCategoryId) revert InvalidCategory();

        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();

        Pool storage winningPool = pools[winningPoolId];
        if (winningPool.categoryId != categoryId) revert PoolNotInCategory();

        // Calculate rake and prize pool
        uint256 rake = cat.totalCollateral * HOUSE_RAKE_BPS / 10000;
        uint256 prizePool = cat.totalCollateral - rake;

        // Update state
        cat.resolved = true;
        cat.winningPoolId = winningPoolId;
        cat.prizePool = prizePool;
        treasury += rake;

        emit CategoryResolved(
            categoryId,
            winningPoolId,
            winningPool.name,
            cat.totalCollateral,
            prizePool,
            rake
        );
    }

    /**
     * @notice Claim winnings from a resolved category
     * @param poolId The winning pool to claim from
     */
    function claim(uint256 poolId) external nonReentrant {
        if (poolId >= nextPoolId) revert InvalidPool();

        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (!cat.resolved) revert CategoryNotResolved();
        if (cat.winningPoolId != poolId) revert NotWinningPool();
        if (claimed[poolId][msg.sender]) revert AlreadyClaimed();

        uint256 userBalance = balances[poolId][msg.sender];
        if (userBalance == 0) revert NoBalance();

        claimed[poolId][msg.sender] = true;

        // Calculate payout: user's share of prize pool
        uint256 redemptionRate = cat.prizePool * PRECISION / pool.totalSupply;
        uint256 payout = userBalance * redemptionRate / PRECISION;

        (bool sent, ) = msg.sender.call{value: payout}("");
        if (!sent) revert TransferFailed();

        emit WinningsClaimed(poolId, msg.sender, userBalance, payout);
    }

    // ============ Curve Math ============

    /**
     * @notice Get current token price for a pool
     * @dev P(S) = CEILING * (1 - e^(-S/K))
     */
    function _getPrice(uint256 supply) internal pure returns (uint256) {
        if (supply == 0) return 0;

        // Calculate e^(-S/K) using our exp approximation
        // Note: supply is in tokens (1e18 scale), K is 50_000e18
        uint256 exponent = supply * PRECISION / K; // S/K scaled
        uint256 expNegative = _expNegative(exponent);

        // P = CEILING * (1 - e^(-S/K))
        return CEILING * (PRECISION - expNegative) / PRECISION;
    }

    /**
     * @notice Calculate cost to buy N tokens from current supply
     * @dev Cost = ∫[S to S+N] P(x) dx = N - K*(e^(-(S+N)/K) - e^(-S/K)) in token units
     *      Scaled to ETH: Cost_ETH = CEILING * [N/1e18 - K/1e18 * (e^(-(S+N)/K) - e^(-S/K))]
     */
    function _calculateCost(uint256 startSupply, uint256 tokens) internal pure returns (uint256) {
        if (tokens == 0) return 0;

        uint256 endSupply = startSupply + tokens;

        // e^(-S/K) and e^(-(S+N)/K)
        uint256 expStart = _expNegative(startSupply * PRECISION / K);
        uint256 expEnd = _expNegative(endSupply * PRECISION / K);

        // Cost = CEILING * [N + K * (expEnd - expStart)]
        // Note: expEnd < expStart, so (expEnd - expStart) is negative
        // Cost = CEILING * N - CEILING * K * (expStart - expEnd) / PRECISION

        uint256 linearPart = CEILING * tokens / PRECISION;
        uint256 curvePart = CEILING * K * (expStart - expEnd) / PRECISION / PRECISION;

        if (curvePart > linearPart) return 0; // Shouldn't happen, but safety
        return linearPart - curvePart;
    }

    /**
     * @notice Calculate tokens received for ETH amount (binary search)
     */
    function _calculateTokensForEth(uint256 startSupply, uint256 ethAmount) internal pure returns (uint256) {
        if (ethAmount == 0) return 0;

        // Binary search for token amount
        uint256 low = 0;
        uint256 high = ethAmount * PRECISION / 1e15; // Upper bound: if price were 0.001

        // Refine upper bound
        if (high > 1e30) high = 1e30; // Cap for safety

        for (uint256 i = 0; i < 100; i++) {
            uint256 mid = (low + high) / 2;
            if (mid == low) break;

            uint256 cost = _calculateCost(startSupply, mid);

            if (cost <= ethAmount) {
                low = mid;
            } else {
                high = mid;
            }
        }

        return low;
    }

    /**
     * @notice Approximate e^(-x) for x >= 0, scaled by PRECISION
     * @dev Uses Taylor series: e^(-x) ≈ 1 - x + x²/2! - x³/3! + x⁴/4! - ...
     *      For large x, returns 0 (which is correct as e^(-∞) = 0)
     */
    function _expNegative(uint256 x) internal pure returns (uint256) {
        if (x == 0) return PRECISION;
        if (x >= 20 * PRECISION) return 0; // e^(-20) ≈ 0

        // For better precision, we use: e^(-x) = 1/e^x
        // And compute e^x using Taylor series

        // Scale down for computation to avoid overflow
        // e^(-x) = (e^(-x/n))^n, we use n based on size of x

        uint256 result = PRECISION;
        uint256 term = PRECISION;

        // Taylor series: e^(-x) = 1 - x + x²/2! - x³/3! + ...
        // We compute enough terms for good precision
        for (uint256 i = 1; i <= 20; i++) {
            term = term * x / (i * PRECISION);
            if (term == 0) break;

            if (i % 2 == 1) {
                if (result > term) {
                    result -= term;
                } else {
                    return 0;
                }
            } else {
                result += term;
            }
        }

        return result;
    }

    // ============ View Functions ============

    /**
     * @notice Get current token price for a pool
     */
    function getCurrentPrice(uint256 poolId) external view returns (uint256) {
        return _getPrice(pools[poolId].totalSupply);
    }

    /**
     * @notice Get expected redemption rate if a pool wins
     * @return Redemption per token (scaled by 1e18), or 0 if pool is empty
     */
    function getExpectedRedemption(uint256 poolId) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (pool.totalSupply == 0) return type(uint256).max;

        uint256 prizePool = cat.totalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
        return prizePool * PRECISION / pool.totalSupply;
    }

    /**
     * @notice Check if a pool can accept bets
     */
    function canBuy(uint256 poolId) external view returns (bool canBuyNow, string memory reason) {
        if (poolId >= nextPoolId) return (false, "Invalid pool");

        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (cat.resolved) return (false, "Category resolved");
        if (block.timestamp >= cat.deadline) return (false, "Betting closed");

        if (cat.totalCollateral < MIN_CATEGORY_COLLATERAL) {
            return (true, "");
        }

        if (_canBuy(poolId, MIN_BET)) {
            return (true, "");
        } else {
            return (false, "Pool oversubscribed - bet on other names");
        }
    }

    /**
     * @notice Simulate a purchase
     * @return tokens Amount of tokens that would be received
     * @return avgPrice Average price paid per token
     * @return expectedRedemption Expected redemption if this pool wins
     * @return profitIfWins Profit in ETH if this pool wins (can be negative!)
     */
    function simulateBuy(uint256 poolId, uint256 ethAmount) external view returns (
        uint256 tokens,
        uint256 avgPrice,
        uint256 expectedRedemption,
        int256 profitIfWins
    ) {
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        tokens = _calculateTokensForEth(pool.totalSupply, ethAmount);
        if (tokens == 0) return (0, 0, 0, 0);

        avgPrice = ethAmount * PRECISION / tokens;

        // Project redemption after this purchase
        uint256 newTotalCollateral = cat.totalCollateral + ethAmount;
        uint256 newPoolSupply = pool.totalSupply + tokens;
        uint256 prizePool = newTotalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
        expectedRedemption = prizePool * PRECISION / newPoolSupply;

        // Calculate profit
        uint256 totalRedemption = tokens * expectedRedemption / PRECISION;
        profitIfWins = int256(totalRedemption) - int256(ethAmount);
    }

    /**
     * @notice Get all pools in a category
     */
    function getCategoryPools(uint256 categoryId) external view returns (uint256[] memory) {
        return categories[categoryId].poolIds;
    }

    /**
     * @notice Get pool details including name
     */
    function getPoolInfo(uint256 poolId) external view returns (
        uint256 categoryId,
        string memory name,
        uint256 totalSupply,
        uint256 collateral,
        uint256 currentPrice
    ) {
        Pool storage pool = pools[poolId];
        return (
            pool.categoryId,
            pool.name,
            pool.totalSupply,
            pool.collateral,
            _getPrice(pool.totalSupply)
        );
    }

    /**
     * @notice Get category details
     */
    function getCategoryInfo(uint256 categoryId) external view returns (
        uint256 year,
        uint256 position,
        Gender gender,
        uint256 totalCollateral,
        uint256 poolCount,
        bool resolved,
        uint256 winningPoolId,
        uint256 prizePool,
        uint256 deadline
    ) {
        Category storage cat = categories[categoryId];
        return (
            cat.year,
            cat.position,
            cat.gender,
            cat.totalCollateral,
            cat.poolIds.length,
            cat.resolved,
            cat.winningPoolId,
            cat.prizePool,
            cat.deadline
        );
    }

    /**
     * @notice Get user's position in a pool
     */
    function getUserPosition(uint256 poolId, address user) external view returns (
        uint256 tokenBalance,
        bool hasClaimed,
        uint256 potentialPayout
    ) {
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        tokenBalance = balances[poolId][user];
        hasClaimed = claimed[poolId][user];

        if (tokenBalance > 0 && pool.totalSupply > 0) {
            uint256 prizePool = cat.resolved
                ? cat.prizePool
                : cat.totalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
            uint256 redemptionRate = prizePool * PRECISION / pool.totalSupply;
            potentialPayout = tokenBalance * redemptionRate / PRECISION;
        }
    }

    /**
     * @notice Calculate cost to buy a specific number of tokens
     */
    function calculateBuyCost(uint256 poolId, uint256 tokenAmount) external view returns (uint256) {
        return _calculateCost(pools[poolId].totalSupply, tokenAmount);
    }

    /**
     * @notice Calculate tokens received for ETH amount
     */
    function calculateTokensForEth(uint256 poolId, uint256 ethAmount) external view returns (uint256) {
        return _calculateTokensForEth(pools[poolId].totalSupply, ethAmount);
    }
}
