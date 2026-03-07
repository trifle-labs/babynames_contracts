// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./BetSlipSVG.sol";

/**
 * @title BabyNameMarket
 * @notice Prediction market for SSA baby name rankings with 1:1 pricing.
 *         Each bet mints an ERC-721 "bet slip" NFT that represents the position.
 * @dev Send X collateral, get X tokens. Parimutuel resolution distributes prize pool.
 *
 * Key Features:
 * - 1:1 pricing: tokens = collateral (transparent, legible)
 * - Each buy() mints a soulbound ERC-721 bet-slip NFT (transfers disabled by default)
 * - Admin can enable transfers via setTransfersEnabled()
 * - Buy-only (no selling) until resolution
 * - 10% house rake taken at resolution
 * - User-created categories and pools
 * - Category types: single position, exacta, trifecta, top-N
 */
contract BabyNameMarket is ERC721, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice House rake in basis points (1000 = 10%)
    uint256 public constant HOUSE_RAKE_BPS = 1000;

    /// @notice Minimum bet amount (18-decimal normalized)
    uint256 public constant MIN_BET = 0.001 ether;

    /// @notice Precision for fixed-point math
    uint256 private constant PRECISION = 1e18;

    // ============ Category Type Constants ============

    uint8 public constant CAT_SINGLE = 0;
    uint8 public constant CAT_EXACTA = 1;
    uint8 public constant CAT_TRIFECTA = 2;
    uint8 public constant CAT_TOP_N = 3;

    // ============ Token Config ============

    /// @notice The ERC20 token used for all collateral (e.g., USDC)
    IERC20 public immutable collateralToken;

    /// @notice Token decimals (e.g., 6 for USDC, 18 for DAI)
    uint8 public immutable tokenDecimals;

    /// @notice Scale factor to normalize token amounts to 18-decimal internal math
    uint256 private immutable scaleFactor;

    // ============ Types ============

    enum Gender { Female, Male }

    struct Pool {
        uint256 categoryId;
        string name;
        uint256 totalSupply;    // Total tokens minted (scaled by 1e18)
        uint256 collateral;     // Collateral collected (normalized to 18 decimals)
    }

    struct Category {
        uint256 year;
        uint256 position;       // Rank being predicted (1-1000) or N for top-N
        uint8 categoryType;     // 0=single, 1=exacta, 2=trifecta, 3=topN
        Gender gender;
        uint256[] poolIds;
        uint256 totalCollateral;
        bool resolved;
        uint256 winningPoolId;      // For single/exacta/trifecta (single winner)
        uint256[] winningPoolIds;   // For topN (multiple winners)
        uint256 prizePool;          // Total collateral minus rake
        uint256 deadline;           // Betting closes at this timestamp
    }

    /// @notice Data stored per bet-slip NFT
    struct BetVoucher {
        uint256 poolId;       // Pool this bet is placed on
        uint256 amount;       // Normalized 1e18 bet amount
        uint256 purchasedAt;  // Block timestamp when the bet was placed
    }

    // ============ State ============

    uint256 public nextPoolId = 1;
    uint256 public nextCategoryId = 1;

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => Category) public categories;
    mapping(uint256 => mapping(address => uint256)) public balances;
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// @notice Publication time per year (year => unix timestamp, 0 = not set)
    mapping(uint256 => uint256) public publicationTimes;

    /// @notice Accumulated house revenue
    uint256 public treasury;

    /// @notice Address authorized to resolve markets
    address public resolver;

    /// @notice Merkle root of valid SSA names (0 = no whitelist enforced)
    bytes32 public namesMerkleRoot;

    /// @notice Names manually approved by owner (keccak256(lowercased) => true)
    mapping(bytes32 => bool) public approvedNames;

    // ============ NFT State ============

    /// @notice Next NFT token ID to mint (starts at 1)
    uint256 public nextTokenId = 1;

    /// @notice Bet slip data per NFT token ID
    mapping(uint256 => BetVoucher) public vouchers;

    /// @notice When true, NFT transfers are allowed; when false, tokens are soulbound
    bool public transfersEnabled;

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

    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event ResolverUpdated(address indexed oldResolver, address indexed newResolver);
    event PoolSubsidized(uint256 indexed poolId, uint256 amount);
    event NamesMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event NameManuallyApproved(string name);

    event PublicationTimeSet(uint256 indexed year, uint256 publicationTime);
    event BetsRefunded(uint256 indexed categoryId, uint256 totalRefunded, uint256 usersRefunded);

    /// @notice Emitted when a bet-slip NFT is minted
    event VoucherMinted(uint256 indexed tokenId, uint256 indexed poolId, address indexed owner, uint256 amount);

    /// @notice Emitted when the transfer-enabled flag is changed by the admin
    event TransfersEnabledSet(bool enabled);

    // ============ Errors ============

    error InvalidCategory();
    error InvalidPool();
    error CategoryAlreadyResolved();
    error CategoryNotResolved();
    error BettingClosed();
    error InsufficientBet();
    error NotWinningPool();
    error AlreadyClaimed();
    error NoBalance();
    error NotResolver();
    error MinOneOption();
    error InvalidPosition();
    error InvalidDeadline();
    error TransferFailed();
    error PoolNotInCategory();
    error InvalidCategoryType();
    error NotTopNCategory();
    error NotSingleWinnerCategory();
    error EmptyWinners();
    error DuplicateWinner();
    error TooManyWinners();
    error InvalidNameProof();
    error PublicationTimeAlreadySet();
    error PublicationTimeNotSet();
    error InvalidPublicationTime();
    error ArrayLengthMismatch();
    error RefundExceedsBalance();
    error TokensNonTransferable();

    // ============ Constructor ============

    constructor(address _resolver, address _token)
        ERC721("Baby Name Market Slip", "BNMS")
        Ownable(msg.sender)
    {
        resolver = _resolver;
        collateralToken = IERC20(_token);
        uint8 d;
        try IERC20Metadata(_token).decimals() returns (uint8 dec) {
            d = dec;
        } catch {
            d = 18;
        }
        tokenDecimals = d;
        scaleFactor = 10 ** (18 - d);
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

        collateralToken.safeTransfer(to, _denormalize(amount));

        emit TreasuryWithdrawn(to, amount);
    }

    /**
     * @notice Inject prize money into a pool without minting tokens
     * @param poolId The pool to subsidize
     * @param amount Token amount in native decimals (e.g., 1000000 for 1 USDC)
     */
    function subsidize(uint256 poolId, uint256 amount) external onlyOwner {
        if (poolId >= nextPoolId) revert InvalidPool();
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 normalizedAmount = _normalize(amount);
        pool.collateral += normalizedAmount;
        cat.totalCollateral += normalizedAmount;

        emit PoolSubsidized(poolId, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set the merkle root for valid SSA names
     * @param root The new merkle root (0 to disable whitelist)
     */
    function setNamesMerkleRoot(bytes32 root) external onlyOwner {
        emit NamesMerkleRootUpdated(namesMerkleRoot, root);
        namesMerkleRoot = root;
    }

    /**
     * @notice Manually approve a name (bypasses merkle check)
     * @param name The name to approve (will be lowercased internally)
     */
    function approveNameManually(string calldata name) external onlyOwner {
        bytes32 hash = keccak256(bytes(_toLowerCase(name)));
        approvedNames[hash] = true;
        emit NameManuallyApproved(name);
    }

    /**
     * @notice Enable or disable NFT transfers.
     * @dev By default transfers are disabled (soulbound). The owner can enable
     *      them at any time to allow secondary-market trading.
     * @param enabled true = transfers allowed; false = soulbound
     */
    function setTransfersEnabled(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersEnabledSet(enabled);
    }

    // ============ ERC-721 Overrides ============

    /**
     * @dev Block transfers unless the owner has explicitly enabled them.
     *      Mints (from == address(0)) and burns (to == address(0)) are
     *      always permitted.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (!transfersEnabled && from != address(0) && to != address(0)) {
            revert TokensNonTransferable();
        }
        return super._update(to, tokenId, auth);
    }

    /**
     * @notice ERC-721 tokenURI returns a fully onchain SVG-based data URI.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        BetVoucher storage v    = vouchers[tokenId];
        Pool storage pool       = pools[v.poolId];
        Category storage cat    = categories[pool.categoryId];

        bool won = false;
        if (cat.resolved) {
            if (cat.categoryType == CAT_TOP_N) {
                won = _isWinningPool(cat, v.poolId);
            } else {
                won = (cat.winningPoolId == v.poolId);
            }
        }

        BetSlipSVG.SlipData memory d = BetSlipSVG.SlipData({
            tokenId:            tokenId,
            poolName:           pool.name,
            year:               cat.year,
            categoryType:       cat.categoryType,
            gender:             uint8(cat.gender),
            position:           cat.position,
            amount:             v.amount,
            tokenDecimals:      tokenDecimals,
            purchasedAt:        v.purchasedAt,
            deadline:           cat.deadline,
            currentTime:        block.timestamp,
            poolCollateral:     pool.collateral,
            categoryCollateral: cat.totalCollateral,
            resolved:           cat.resolved,
            won:                won
        });

        return BetSlipSVG.tokenURI(d);
    }

    // ============ Publication Time & Refunds ============

    /**
     * @notice Set the publication time for a year (when SSA data was published)
     * @param year The SSA data year (e.g., 2025)
     * @param _publicationTime Unix timestamp when SSA data was published
     */
    function setPublicationTime(
        uint256 year,
        uint256 _publicationTime
    ) external onlyResolver {
        if (publicationTimes[year] != 0) revert PublicationTimeAlreadySet();
        if (_publicationTime == 0 || _publicationTime > block.timestamp) revert InvalidPublicationTime();

        publicationTimes[year] = _publicationTime;

        emit PublicationTimeSet(year, _publicationTime);
    }

    /**
     * @notice Refund bets placed after the publication time
     * @param categoryId The category to refund from
     * @param poolIds Pool IDs for each refund entry
     * @param users User addresses for each refund entry
     * @param tokenAmounts Token amounts to remove from each user's balance
     * @param collateralAmounts Collateral amounts to refund to each user (18-decimal normalized)
     */
    function refundInvalidBets(
        uint256 categoryId,
        uint256[] calldata poolIds,
        address[] calldata users,
        uint256[] calldata tokenAmounts,
        uint256[] calldata collateralAmounts
    ) external onlyResolver nonReentrant {
        if (categoryId >= nextCategoryId) revert InvalidCategory();
        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();
        if (publicationTimes[cat.year] == 0) revert PublicationTimeNotSet();

        uint256 len = poolIds.length;
        if (len != users.length || len != tokenAmounts.length || len != collateralAmounts.length) {
            revert ArrayLengthMismatch();
        }

        uint256 totalRefunded = 0;

        for (uint256 i = 0; i < len; i++) {
            if (pools[poolIds[i]].categoryId != categoryId) revert PoolNotInCategory();
            if (balances[poolIds[i]][users[i]] < tokenAmounts[i]) revert RefundExceedsBalance();

            // Adjust balances and pool state
            balances[poolIds[i]][users[i]] -= tokenAmounts[i];
            pools[poolIds[i]].totalSupply -= tokenAmounts[i];
            pools[poolIds[i]].collateral -= collateralAmounts[i];
            cat.totalCollateral -= collateralAmounts[i];

            // Transfer refund to user
            collateralToken.safeTransfer(users[i], _denormalize(collateralAmounts[i]));
            totalRefunded += collateralAmounts[i];
        }

        emit BetsRefunded(categoryId, totalRefunded, len);
    }

    // ============ Category Management ============

    /**
     * @notice Create a new prediction category with initial pools
     * @param year The year of SSA data (e.g., 2025)
     * @param position The rank being predicted (1-1000) or N for top-N categories
     * @param categoryType 0=single, 1=exacta, 2=trifecta, 3=topN
     * @param gender Male or Female
     * @param names Initial pool names (minimum 1)
     * @param deadline Timestamp when betting closes
     * @param proofs Merkle proofs for each name (only checked for single/topN types)
     */
    function createCategory(
        uint256 year,
        uint256 position,
        uint8 categoryType,
        Gender gender,
        string[] calldata names,
        uint256 deadline,
        bytes32[][] calldata proofs
    ) external whenNotPaused returns (uint256 categoryId) {
        if (names.length < 1) revert MinOneOption();
        if (categoryType > CAT_TOP_N) revert InvalidCategoryType();
        if (position < 1 || position > 1000) revert InvalidPosition();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        // Validate names for single and topN categories
        if (categoryType == CAT_SINGLE || categoryType == CAT_TOP_N) {
            for (uint256 i = 0; i < names.length; i++) {
                bytes32[] memory emptyProof = new bytes32[](0);
                if (!_isValidName(names[i], i < proofs.length ? proofs[i] : emptyProof)) revert InvalidNameProof();
            }
        }

        categoryId = nextCategoryId++;

        Category storage cat = categories[categoryId];
        cat.year = year;
        cat.position = position;
        cat.categoryType = categoryType;
        cat.gender = gender;
        cat.deadline = deadline;

        for (uint256 i = 0; i < names.length; i++) {
            _createPool(categoryId, names[i]);
        }

        emit CategoryCreated(categoryId, year, position, categoryType, gender, deadline);
    }

    /**
     * @notice Add a new name option to an existing category
     * @param categoryId The category to add to
     * @param name The name to add as a betting option
     * @param proof Merkle proof for the name (only checked for single/topN types)
     */
    function addNameToCategory(
        uint256 categoryId,
        string calldata name,
        bytes32[] calldata proof
    ) external whenNotPaused returns (uint256 poolId) {
        if (categoryId >= nextCategoryId) revert InvalidCategory();
        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();
        if (block.timestamp >= cat.deadline) revert BettingClosed();

        // Validate name for single and topN categories
        if (cat.categoryType == CAT_SINGLE || cat.categoryType == CAT_TOP_N) {
            if (!_isValidName(name, proof)) revert InvalidNameProof();
        }

        poolId = _createPool(categoryId, name);
    }

    /**
     * @notice Add a new name and place a bet in a single transaction
     * @param categoryId The category to add to
     * @param name The name to add as a betting option
     * @param proof Merkle proof for the name (only checked for single/topN types)
     * @param amount Token amount in native decimals (e.g., 1000000 for 1 USDC)
     */
    function addNameAndBuy(
        uint256 categoryId,
        string calldata name,
        bytes32[] calldata proof,
        uint256 amount
    ) external nonReentrant whenNotPaused returns (uint256 poolId) {
        if (categoryId >= nextCategoryId) revert InvalidCategory();
        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();
        if (block.timestamp >= cat.deadline) revert BettingClosed();

        // Validate name for single and topN categories
        if (cat.categoryType == CAT_SINGLE || cat.categoryType == CAT_TOP_N) {
            if (!_isValidName(name, proof)) revert InvalidNameProof();
        }

        poolId = _createPool(categoryId, name);

        // Place bet if amount > 0
        if (amount > 0) {
            uint256 normalizedAmount = _normalize(amount);
            if (normalizedAmount < MIN_BET) revert InsufficientBet();

            // Transfer tokens from buyer
            collateralToken.safeTransferFrom(msg.sender, address(this), amount);

            // 1:1 pricing: tokens = normalizedAmount
            pools[poolId].totalSupply += normalizedAmount;
            pools[poolId].collateral += normalizedAmount;
            cat.totalCollateral += normalizedAmount;
            balances[poolId][msg.sender] += normalizedAmount;

            // Mint bet-slip NFT
            uint256 tokenId = nextTokenId++;
            vouchers[tokenId] = BetVoucher({
                poolId:      poolId,
                amount:      normalizedAmount,
                purchasedAt: block.timestamp
            });
            _mint(msg.sender, tokenId);

            emit TokensPurchased(poolId, msg.sender, normalizedAmount, normalizedAmount, PRECISION);
            emit VoucherMinted(tokenId, poolId, msg.sender, normalizedAmount);
        }
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

    // ============ Name Validation ============

    function _isValidName(string calldata name, bytes32[] memory proof) internal view returns (bool) {
        // No whitelist set = all names allowed
        if (namesMerkleRoot == bytes32(0)) return true;

        string memory lowered = _toLowerCase(name);
        bytes32 nameHash = keccak256(bytes(lowered));

        // Check manual approval
        if (approvedNames[nameHash]) return true;

        // Check merkle proof (double-hash leaf format matches OZ StandardMerkleTree)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(lowered))));
        return MerkleProof.verify(proof, namesMerkleRoot, leaf);
    }

    function _toLowerCase(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                b[i] = bytes1(uint8(b[i]) + 32);
            }
        }
        return string(b);
    }

    // ============ Trading ============

    /**
     * @notice Purchase tokens in a pool (1:1 pricing)
     * @param poolId The pool to buy into
     * @param amount Token amount in native decimals (e.g., 1000000 for 1 USDC)
     */
    function buy(uint256 poolId, uint256 amount) external nonReentrant whenNotPaused {
        if (poolId >= nextPoolId) revert InvalidPool();

        uint256 normalizedAmount = _normalize(amount);
        if (normalizedAmount < MIN_BET) revert InsufficientBet();

        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        if (cat.resolved) revert CategoryAlreadyResolved();
        if (block.timestamp >= cat.deadline) revert BettingClosed();

        // Transfer tokens from buyer
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        // 1:1 pricing: tokens = normalizedAmount
        pool.totalSupply += normalizedAmount;
        pool.collateral += normalizedAmount;
        cat.totalCollateral += normalizedAmount;
        balances[poolId][msg.sender] += normalizedAmount;

        // Mint bet-slip NFT
        uint256 tokenId = nextTokenId++;
        vouchers[tokenId] = BetVoucher({
            poolId:      poolId,
            amount:      normalizedAmount,
            purchasedAt: block.timestamp
        });
        _mint(msg.sender, tokenId);

        emit TokensPurchased(poolId, msg.sender, normalizedAmount, normalizedAmount, PRECISION);
        emit VoucherMinted(tokenId, poolId, msg.sender, normalizedAmount);
    }

    // ============ Resolution ============

    /**
     * @notice Resolve a single-winner category (single/exacta/trifecta)
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
        if (cat.categoryType == CAT_TOP_N) revert NotSingleWinnerCategory();

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
     * @notice Resolve a top-N category with multiple winning pools
     * @param categoryId The category to resolve
     * @param _winningPoolIds Array of pool IDs that won (names in top N)
     */
    function resolveTopN(
        uint256 categoryId,
        uint256[] calldata _winningPoolIds
    ) external onlyResolver {
        if (categoryId >= nextCategoryId) revert InvalidCategory();

        Category storage cat = categories[categoryId];
        if (cat.resolved) revert CategoryAlreadyResolved();
        if (cat.categoryType != CAT_TOP_N) revert NotTopNCategory();
        if (_winningPoolIds.length == 0) revert EmptyWinners();
        if (_winningPoolIds.length > cat.position) revert TooManyWinners();

        // Validate all pools belong to this category and no duplicates
        for (uint256 i = 0; i < _winningPoolIds.length; i++) {
            if (pools[_winningPoolIds[i]].categoryId != categoryId) revert PoolNotInCategory();
            for (uint256 j = 0; j < i; j++) {
                if (_winningPoolIds[i] == _winningPoolIds[j]) revert DuplicateWinner();
            }
        }

        // Calculate rake and prize pool
        uint256 rake = cat.totalCollateral * HOUSE_RAKE_BPS / 10000;
        uint256 prizePool = cat.totalCollateral - rake;

        // Update state
        cat.resolved = true;
        cat.prizePool = prizePool;
        treasury += rake;

        // Store winning pool IDs
        for (uint256 i = 0; i < _winningPoolIds.length; i++) {
            cat.winningPoolIds.push(_winningPoolIds[i]);
        }

        emit CategoryResolvedTopN(
            categoryId,
            _winningPoolIds,
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
        if (claimed[poolId][msg.sender]) revert AlreadyClaimed();

        uint256 userBalance = balances[poolId][msg.sender];
        if (userBalance == 0) revert NoBalance();

        uint256 payout;

        if (cat.categoryType == CAT_TOP_N) {
            // Multi-winner: check pool is in winning set
            if (!_isWinningPool(cat, poolId)) revert NotWinningPool();

            // Calculate total supply across all winning pools
            uint256 totalWinningSupply = 0;
            for (uint256 i = 0; i < cat.winningPoolIds.length; i++) {
                totalWinningSupply += pools[cat.winningPoolIds[i]].totalSupply;
            }

            // Payout: user's share of entire prize pool across all winning pools
            uint256 redemptionRate = cat.prizePool * PRECISION / totalWinningSupply;
            payout = userBalance * redemptionRate / PRECISION;
        } else {
            // Single winner
            if (cat.winningPoolId != poolId) revert NotWinningPool();

            uint256 redemptionRate = cat.prizePool * PRECISION / pool.totalSupply;
            payout = userBalance * redemptionRate / PRECISION;
        }

        claimed[poolId][msg.sender] = true;

        collateralToken.safeTransfer(msg.sender, _denormalize(payout));

        emit WinningsClaimed(poolId, msg.sender, userBalance, payout);
    }

    /**
     * @notice Check if a pool is in the winning set for a top-N category
     */
    function _isWinningPool(Category storage cat, uint256 poolId) internal view returns (bool) {
        for (uint256 i = 0; i < cat.winningPoolIds.length; i++) {
            if (cat.winningPoolIds[i] == poolId) return true;
        }
        return false;
    }

    // ============ Token Normalization ============

    /// @notice Convert native token amount to 18-decimal internal representation
    function _normalize(uint256 amount) internal view returns (uint256) {
        return amount * scaleFactor;
    }

    /// @notice Convert 18-decimal internal amount to native token decimals
    function _denormalize(uint256 amount) internal view returns (uint256) {
        return amount / scaleFactor;
    }

    // ============ View Functions ============

    /**
     * @notice Get expected redemption rate if a pool wins
     * @return Redemption per token (scaled by 1e18), or max uint if pool is empty
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

        return (true, "");
    }

    /**
     * @notice Simulate a purchase (1:1 pricing)
     * @param poolId The pool to simulate buying into
     * @param amount Token amount in native decimals
     * @return tokens Amount of tokens that would be received (= normalizedAmount)
     * @return avgPrice Average price paid per token (always PRECISION = 1e18)
     * @return expectedRedemption Expected redemption if this pool wins
     * @return profitIfWins Profit (normalized) if this pool wins
     */
    function simulateBuy(uint256 poolId, uint256 amount) external view returns (
        uint256 tokens,
        uint256 avgPrice,
        uint256 expectedRedemption,
        int256 profitIfWins
    ) {
        Pool storage pool = pools[poolId];
        Category storage cat = categories[pool.categoryId];

        uint256 normalizedAmount = _normalize(amount);
        if (normalizedAmount == 0) return (0, 0, 0, 0);

        tokens = normalizedAmount;
        avgPrice = PRECISION;

        // Project redemption after this purchase
        uint256 newTotalCollateral = cat.totalCollateral + normalizedAmount;
        uint256 newPoolSupply = pool.totalSupply + tokens;
        uint256 prizePool = newTotalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
        expectedRedemption = prizePool * PRECISION / newPoolSupply;

        // Calculate profit
        uint256 totalRedemption = tokens * expectedRedemption / PRECISION;
        profitIfWins = int256(totalRedemption) - int256(normalizedAmount);
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
            PRECISION // 1:1 pricing: always $1
        );
    }

    /**
     * @notice Get category details
     */
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
    ) {
        Category storage cat = categories[categoryId];
        return (
            cat.year,
            cat.position,
            cat.categoryType,
            cat.gender,
            cat.totalCollateral,
            cat.poolIds.length,
            cat.resolved,
            cat.winningPoolId,
            cat.prizePool,
            cat.deadline,
            publicationTimes[cat.year]
        );
    }

    /**
     * @notice Get winning pool IDs for a top-N category
     */
    function getWinningPoolIds(uint256 categoryId) external view returns (uint256[] memory) {
        return categories[categoryId].winningPoolIds;
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
            if (cat.categoryType == CAT_TOP_N && cat.resolved) {
                // For resolved topN, compute payout across all winning pools
                if (_isWinningPool(cat, poolId)) {
                    uint256 totalWinningSupply = 0;
                    for (uint256 i = 0; i < cat.winningPoolIds.length; i++) {
                        totalWinningSupply += pools[cat.winningPoolIds[i]].totalSupply;
                    }
                    uint256 redemptionRate = cat.prizePool * PRECISION / totalWinningSupply;
                    potentialPayout = tokenBalance * redemptionRate / PRECISION;
                }
                // else: not a winning pool, potentialPayout stays 0
            } else {
                uint256 prizePool = cat.resolved
                    ? cat.prizePool
                    : cat.totalCollateral * (10000 - HOUSE_RAKE_BPS) / 10000;
                uint256 redemptionRate = prizePool * PRECISION / pool.totalSupply;
                potentialPayout = tokenBalance * redemptionRate / PRECISION;
            }
        }
    }
}
