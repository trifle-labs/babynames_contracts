// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBabyNameMarket
 * @notice Interface for BabyNameMarket prediction market (1:1 pricing, ERC20 collateral)
 */
interface IBabyNameMarket {

    enum Gender { Female, Male }

    // ============ Events ============

    event CategoryCreated(
        uint256 indexed categoryId,
        uint256 year,
        uint256 position,
        uint8 categoryType,
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

    event CategoryResolvedTopN(
        uint256 indexed categoryId,
        uint256[] winningPoolIds,
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
    event NamesMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event NameManuallyApproved(string name);
    event PublicationTimeSet(uint256 indexed year, uint256 publicationTime);
    event BetsRefunded(uint256 indexed categoryId, uint256 totalRefunded, uint256 usersRefunded);
    event VoucherMinted(uint256 indexed tokenId, uint256 indexed poolId, address indexed owner, uint256 amount);
    event TransfersEnabledSet(bool enabled);

    // ============ Category Management ============

    function createCategory(
        uint256 year,
        uint256 position,
        uint8 categoryType,
        Gender gender,
        string[] calldata names,
        uint256 deadline,
        bytes32[][] calldata proofs
    ) external returns (uint256 categoryId);

    function addNameToCategory(
        uint256 categoryId,
        string calldata name,
        bytes32[] calldata proof
    ) external returns (uint256 poolId);

    function addNameAndBuy(
        uint256 categoryId,
        string calldata name,
        bytes32[] calldata proof,
        uint256 amount
    ) external returns (uint256 poolId);

    // ============ Trading ============

    function buy(uint256 poolId, uint256 amount) external;

    // ============ Admin ============

    function subsidize(uint256 poolId, uint256 amount) external;

    // ============ Publication Time & Refunds ============

    function setPublicationTime(uint256 year, uint256 publicationTime) external;
    function publicationTimes(uint256 year) external view returns (uint256);

    function refundInvalidBets(
        uint256 categoryId,
        uint256[] calldata poolIds,
        address[] calldata users,
        uint256[] calldata tokenAmounts,
        uint256[] calldata collateralAmounts
    ) external;

    // ============ Resolution ============

    function resolve(uint256 categoryId, uint256 winningPoolId) external;

    function resolveTopN(uint256 categoryId, uint256[] calldata winningPoolIds) external;

    function claim(uint256 poolId) external;

    // ============ View Functions ============

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
        uint8 categoryType,
        Gender gender,
        uint256 totalCollateral,
        uint256 poolCount,
        bool resolved,
        uint256 winningPoolId,
        uint256 prizePool,
        uint256 deadline,
        uint256 publicationTime
    );

    function getWinningPoolIds(uint256 categoryId) external view returns (uint256[] memory);

    function getUserPosition(uint256 poolId, address user) external view returns (
        uint256 tokenBalance,
        bool hasClaimed,
        uint256 potentialPayout
    );

    // ============ Constants ============

    function HOUSE_RAKE_BPS() external view returns (uint256);
    function MIN_BET() external view returns (uint256);
    function CAT_SINGLE() external view returns (uint8);
    function CAT_EXACTA() external view returns (uint8);
    function CAT_TRIFECTA() external view returns (uint8);
    function CAT_TOP_N() external view returns (uint8);

    // ============ Token Config ============

    function collateralToken() external view returns (IERC20);
    function tokenDecimals() external view returns (uint8);

    // ============ Admin ============

    function setNamesMerkleRoot(bytes32 root) external;
    function approveNameManually(string calldata name) external;
    function setTransfersEnabled(bool enabled) external;

    // ============ State ============

    function treasury() external view returns (uint256);
    function resolver() external view returns (address);
    function namesMerkleRoot() external view returns (bytes32);
    function approvedNames(bytes32 nameHash) external view returns (bool);
    function nextPoolId() external view returns (uint256);
    function nextCategoryId() external view returns (uint256);
    function balances(uint256 poolId, address user) external view returns (uint256);
    function claimed(uint256 poolId, address user) external view returns (bool);

    // ============ NFT ============

    function nextTokenId() external view returns (uint256);
    function transfersEnabled() external view returns (bool);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
