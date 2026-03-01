// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBabyNameMarket
 * @notice Interface for BabyNameMarket prediction market (ERC20 collateral)
 */
interface IBabyNameMarket {

    enum Gender { Female, Male }

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

    event PoolSubsidized(uint256 indexed poolId, uint256 amount);

    // ============ Category Management ============

    function createCategory(
        uint256 year,
        uint256 position,
        Gender gender,
        string[] calldata names,
        uint256 deadline
    ) external returns (uint256 categoryId);

    function addNameToCategory(
        uint256 categoryId,
        string calldata name
    ) external returns (uint256 poolId);

    // ============ Trading ============

    function buy(uint256 poolId, uint256 amount) external;

    // ============ Admin ============

    function subsidize(uint256 poolId, uint256 amount) external;

    // ============ Resolution ============

    function resolve(uint256 categoryId, uint256 winningPoolId) external;

    function claim(uint256 poolId) external;

    // ============ View Functions ============

    function getCurrentPrice(uint256 poolId) external view returns (uint256);

    function getExpectedRedemption(uint256 poolId) external view returns (uint256);

    function canBuy(uint256 poolId) external view returns (bool canBuyNow, string memory reason);

    function simulateBuy(uint256 poolId, uint256 amount) external view returns (
        uint256 tokens,
        uint256 avgPrice,
        uint256 expectedRedemption,
        int256 profitIfWins
    );

    function getCategoryPools(uint256 categoryId) external view returns (uint256[] memory);

    function getPoolInfo(uint256 poolId) external view returns (
        uint256 categoryId,
        string memory name,
        uint256 totalSupply,
        uint256 collateral,
        uint256 currentPrice
    );

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
    );

    function getUserPosition(uint256 poolId, address user) external view returns (
        uint256 tokenBalance,
        bool hasClaimed,
        uint256 potentialPayout
    );

    function calculateBuyCost(uint256 poolId, uint256 tokenAmount) external view returns (uint256);

    function calculateTokensForAmount(uint256 poolId, uint256 amount) external view returns (uint256);

    // ============ Constants ============

    function CEILING() external view returns (uint256);
    function K() external view returns (uint256);
    function HOUSE_RAKE_BPS() external view returns (uint256);
    function MIN_CATEGORY_COLLATERAL() external view returns (uint256);
    function MIN_BET() external view returns (uint256);

    // ============ Token Config ============

    function collateralToken() external view returns (IERC20);
    function tokenDecimals() external view returns (uint8);

    // ============ State ============

    function treasury() external view returns (uint256);
    function resolver() external view returns (address);
    function nextPoolId() external view returns (uint256);
    function nextCategoryId() external view returns (uint256);
    function balances(uint256 poolId, address user) external view returns (uint256);
    function claimed(uint256 poolId, address user) external view returns (bool);
}
