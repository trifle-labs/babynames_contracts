// SPDX-License-Identifier: BUSL-1.1
// Based on Context Markets contracts, used under license
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {EfficientHashLib} from "solady/utils/EfficientHashLib.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {PredictionMarket} from "./PredictionMarket.sol";

/**
 * @title Vault
 * @notice Commitment-based market bootstrapping for baby name prediction markets.
 *
 *         Markets are scoped to (name, year, region). Each combination can only have
 *         one active proposal at a time. Years are locked by default and must be opened
 *         by the admin before proposals can be created.
 *
 *         Anyone can propose a market for a name in the Merkle tree and commit capital.
 *         Once commitments cross the launch threshold, anyone can trigger market creation.
 *         All committed trades execute simultaneously at the same initial 50/50 prices.
 *
 *         After launch, users call claimShares() to receive outcome tokens directly
 *         to their wallet — they can trade freely on PredictionMarket immediately.
 *
 *         Market creation fees are paid from a separate feeSource address, not from
 *         committed user funds.
 */
contract Vault is OwnableRoles {
    PredictionMarket public predictionMarket;
    IERC20 public usdc;

    // ========== NAME VALIDATION ==========

    /// @notice Merkle root of valid SSA names (0 = no whitelist enforced, all names allowed)
    bytes32 public namesMerkleRoot;

    /// @notice Names manually approved by owner (keccak256(lowercased) => true)
    mapping(bytes32 => bool) public approvedNames;

    // ========== YEAR LIFECYCLE ==========

    /// @notice Whether a year is open for new proposals. Years are locked by default.
    mapping(uint16 => bool) public yearOpen;

    // ========== DEFAULT MARKET PARAMS ==========

    address public defaultOracle;
    uint256 public defaultLaunchThreshold;
    uint256 public defaultDeadlineDuration;
    address public surplusRecipient;

    /// @notice Address that pays market creation fees (separate from committed user funds)
    address public feeSource;

    // ========== PROPOSAL STATE ==========

    enum ProposalState {
        OPEN,
        LAUNCHED,
        EXPIRED,
        CANCELLED
    }

    struct ProposalInfo {
        bytes32 questionId;
        address oracle;
        bytes metadata;
        string[] outcomeNames;
        uint256 launchThreshold;
        uint256 deadline;
        ProposalState state;
        bytes32 marketId;
        uint256[] totalPerOutcome;
        uint256 totalCommitted;
        address[] committers;
        string name;
        uint16 year;
        string region;
        uint256 actualCost;
        uint256[] totalSharesPerOutcome;
    }

    struct ProposalStorage {
        bytes32 questionId;
        address oracle;
        bytes metadata;
        string[] outcomeNames;
        uint256 launchThreshold;
        uint256 deadline;
        ProposalState state;
        bytes32 marketId;
        uint256[] totalPerOutcome;
        uint256 totalCommitted;
        address[] committers;
        string name;
        uint16 year;
        string region;
        uint256 actualCost;
        uint256[] totalSharesPerOutcome;
        mapping(address => uint256[]) committed;
        mapping(address => bool) hasCommitted;
        mapping(address => bool) claimed;
    }

    mapping(bytes32 => ProposalStorage) internal proposals;

    /// @notice Maps market key hash(name, year, region) to proposalId.
    ///         Prevents duplicate proposals for the same (name, year, region) combination.
    mapping(bytes32 => bytes32) public marketKeyToProposal;

    mapping(address => uint256) public pendingRefunds;

    // ========== EVENTS ==========

    event ProposalCreated(
        bytes32 indexed proposalId,
        bytes32 indexed questionId,
        string name,
        uint16 year,
        string region,
        address proposer,
        uint256 launchThreshold,
        uint256 deadline
    );
    event Committed(bytes32 indexed proposalId, address indexed user, uint256[] amounts, uint256 total);
    event CommitmentWithdrawn(bytes32 indexed proposalId, address indexed user, uint256 amount);
    event MarketLaunched(
        bytes32 indexed proposalId, bytes32 indexed marketId, uint256 actualCost, uint256 committerCount
    );
    event SharesClaimed(bytes32 indexed proposalId, address indexed user, uint256[] shares, uint256 refund);
    event ProposalCancelled(bytes32 indexed proposalId);
    event RefundClaimed(address indexed user, uint256 amount);
    event SurplusRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeeSourceUpdated(address indexed oldSource, address indexed newSource);
    event NamesMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event NameApproved(string name);
    event DefaultOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DefaultLaunchThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event DefaultDeadlineDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event YearOpened(uint16 indexed year);
    event YearClosed(uint16 indexed year);

    // ========== ERRORS ==========

    error NotOpen();
    error NotLaunched();
    error AlreadyClaimed();
    error DeadlinePassed();
    error InvalidAmounts();
    error ProposalExists();
    error DuplicateMarketKey();
    error InvalidDeadline();
    error InvalidThreshold();
    error InvalidOracle();
    error InvalidOutcomes();
    error InvalidName();
    error InvalidYear();
    error YearNotOpen();
    error BelowThreshold();
    error NotWithdrawable();
    error NothingToWithdraw();
    error NothingToClaim();
    error TransferFailed();
    error ZeroAddress();
    error DefaultsNotSet();

    constructor(
        address _predictionMarket,
        address _surplusRecipient,
        address _feeSource,
        address _defaultOracle,
        uint256 _defaultLaunchThreshold,
        uint256 _defaultDeadlineDuration,
        address _owner
    ) {
        _initializeOwner(_owner);
        predictionMarket = PredictionMarket(_predictionMarket);
        usdc = PredictionMarket(_predictionMarket).usdc();

        if (_surplusRecipient == address(0)) revert ZeroAddress();
        surplusRecipient = _surplusRecipient;
        emit SurplusRecipientUpdated(address(0), _surplusRecipient);

        if (_feeSource == address(0)) revert ZeroAddress();
        feeSource = _feeSource;
        emit FeeSourceUpdated(address(0), _feeSource);

        if (_defaultOracle == address(0)) revert InvalidOracle();
        defaultOracle = _defaultOracle;
        emit DefaultOracleUpdated(address(0), _defaultOracle);

        defaultLaunchThreshold = _defaultLaunchThreshold;
        emit DefaultLaunchThresholdUpdated(0, _defaultLaunchThreshold);

        defaultDeadlineDuration = _defaultDeadlineDuration;
        emit DefaultDeadlineDurationUpdated(0, _defaultDeadlineDuration);

        // All years are locked by default — admin must openYear() before proposals can be created

        usdc.approve(_predictionMarket, type(uint256).max);
    }

    // ========== ADMIN ==========

    function openYear(uint16 year) external onlyOwner {
        if (year == 0) revert InvalidYear();
        yearOpen[year] = true;
        emit YearOpened(year);
    }

    function closeYear(uint16 year) external onlyOwner {
        yearOpen[year] = false;
        emit YearClosed(year);
    }

    function setNamesMerkleRoot(bytes32 _root) external onlyOwner {
        emit NamesMerkleRootUpdated(namesMerkleRoot, _root);
        namesMerkleRoot = _root;
    }

    function approveName(string calldata name) external onlyOwner {
        bytes32 nameHash = keccak256(bytes(_toLowerCase(name)));
        approvedNames[nameHash] = true;
        emit NameApproved(name);
    }

    function setSurplusRecipient(address _surplusRecipient) external onlyOwner {
        if (_surplusRecipient == address(0)) revert ZeroAddress();
        emit SurplusRecipientUpdated(surplusRecipient, _surplusRecipient);
        surplusRecipient = _surplusRecipient;
    }

    function setFeeSource(address _feeSource) external onlyOwner {
        if (_feeSource == address(0)) revert ZeroAddress();
        emit FeeSourceUpdated(feeSource, _feeSource);
        feeSource = _feeSource;
    }

    function setDefaultOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert InvalidOracle();
        emit DefaultOracleUpdated(defaultOracle, _oracle);
        defaultOracle = _oracle;
    }

    function setDefaultLaunchThreshold(uint256 _threshold) external onlyOwner {
        emit DefaultLaunchThresholdUpdated(defaultLaunchThreshold, _threshold);
        defaultLaunchThreshold = _threshold;
    }

    function setDefaultDeadlineDuration(uint256 _duration) external onlyOwner {
        emit DefaultDeadlineDurationUpdated(defaultDeadlineDuration, _duration);
        defaultDeadlineDuration = _duration;
    }

    function setUsdcAllowance(uint256 amount) external onlyOwner {
        usdc.approve(address(predictionMarket), amount);
    }

    function withdrawUsdc(uint256 amount, address to) external onlyOwner {
        if (!usdc.transfer(to, amount)) revert TransferFailed();
    }

    // ========== NAME VALIDATION ==========

    function isValidName(string memory name, bytes32[] calldata proof) public view returns (bool) {
        if (namesMerkleRoot == bytes32(0)) return true;

        string memory lowered = _toLowerCase(name);
        bytes32 nameHash = keccak256(bytes(lowered));

        if (approvedNames[nameHash]) return true;

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(lowered))));
        return MerkleProofLib.verify(proof, namesMerkleRoot, leaf);
    }

    // ========== PROPOSALS ==========

    /**
     * @notice Proposes a market for a name and commits capital in one call.
     *         Uses the national region by default. Year must be open.
     * @param name The baby name to create a market for
     * @param year The SSA data year (e.g. 2025, 2026)
     * @param proof Merkle proof that the name is in the valid names tree
     * @param amounts Commitment amounts per outcome [YES, NO]
     */
    function propose(string calldata name, uint16 year, bytes32[] calldata proof, uint256[] calldata amounts)
        external
        returns (bytes32)
    {
        return _propose(name, year, "", proof, amounts);
    }

    /**
     * @notice Proposes a market for a name in a specific region.
     *         Region is a state name (e.g. "california") or "" for national.
     */
    function proposeRegional(
        string calldata name,
        uint16 year,
        string calldata region,
        bytes32[] calldata proof,
        uint256[] calldata amounts
    ) external returns (bytes32) {
        return _propose(name, year, region, proof, amounts);
    }

    function _propose(
        string calldata name,
        uint16 year,
        string memory region,
        bytes32[] calldata proof,
        uint256[] calldata amounts
    ) internal returns (bytes32) {
        if (!isValidName(name, proof)) revert InvalidName();
        if (!yearOpen[year]) revert YearNotOpen();
        if (defaultOracle == address(0)) revert DefaultsNotSet();
        if (defaultDeadlineDuration == 0) revert DefaultsNotSet();
        if (defaultLaunchThreshold == 0) revert DefaultsNotSet();

        string memory lowered = _toLowerCase(name);
        string memory loweredRegion = _toLowerCase(region);

        // Unique key per (name, year, region)
        bytes32 marketKey = keccak256(abi.encode(lowered, year, loweredRegion));

        // Prevent duplicate active proposals for the same (name, year, region)
        if (marketKeyToProposal[marketKey] != bytes32(0)) {
            bytes32 existingId = marketKeyToProposal[marketKey];
            ProposalStorage storage existing = proposals[existingId];
            if (
                existing.state == ProposalState.OPEN || existing.state == ProposalState.LAUNCHED
            ) {
                revert DuplicateMarketKey();
            }
        }

        // questionId: vault address (20 bytes) + hash(name, year, region) truncated (12 bytes)
        bytes32 questionId = bytes32(
            (uint256(uint160(address(this))) << 96) | uint256(uint96(bytes12(marketKey)))
        );

        bytes32 proposalId =
            keccak256(abi.encodePacked(address(this), block.chainid, questionId, block.timestamp));
        if (proposals[proposalId].deadline != 0) revert ProposalExists();

        string[] memory outcomeNames = new string[](2);
        outcomeNames[0] = "YES";
        outcomeNames[1] = "NO";

        uint256 deadline = block.timestamp + defaultDeadlineDuration;

        ProposalStorage storage prop = proposals[proposalId];
        prop.questionId = questionId;
        prop.oracle = defaultOracle;
        prop.metadata = abi.encode(lowered, year, loweredRegion);
        prop.outcomeNames = outcomeNames;
        prop.launchThreshold = defaultLaunchThreshold;
        prop.deadline = deadline;
        prop.state = ProposalState.OPEN;
        prop.totalPerOutcome = new uint256[](2);
        prop.name = lowered;
        prop.year = year;
        prop.region = loweredRegion;

        marketKeyToProposal[marketKey] = proposalId;

        emit ProposalCreated(
            proposalId, questionId, lowered, year, loweredRegion, msg.sender, defaultLaunchThreshold, deadline
        );

        if (amounts.length != 2) revert InvalidAmounts();
        _commit(proposalId, amounts);

        return proposalId;
    }

    /**
     * @notice Admin creates a proposal with custom parameters, bypassing name/year validation.
     * @param year The SSA data year
     * @param region Region string ("" for national, or state name)
     */
    function adminPropose(
        string[] calldata outcomeNames,
        address oracle,
        bytes calldata metadata,
        uint16 year,
        string calldata region,
        uint256 launchThreshold,
        uint256 deadline
    ) external onlyOwner returns (bytes32) {
        if (outcomeNames.length < 2) revert InvalidOutcomes();
        if (oracle == address(0)) revert InvalidOracle();
        if (year == 0) revert InvalidYear();

        uint256 _threshold = launchThreshold > 0 ? launchThreshold : defaultLaunchThreshold;
        uint256 _deadline = deadline > 0 ? deadline : block.timestamp + defaultDeadlineDuration;
        if (_threshold == 0) revert InvalidThreshold();
        if (_deadline <= block.timestamp) revert InvalidDeadline();

        bytes32 metaHash = keccak256(abi.encode(metadata, year, region));
        bytes32 questionId = bytes32(
            (uint256(uint160(address(this))) << 96) | uint256(uint96(bytes12(metaHash)))
        );

        bytes32 proposalId =
            keccak256(abi.encodePacked(address(this), block.chainid, questionId, block.timestamp));
        if (proposals[proposalId].deadline != 0) revert ProposalExists();

        ProposalStorage storage prop = proposals[proposalId];
        prop.questionId = questionId;
        prop.oracle = oracle;
        prop.metadata = metadata;
        prop.outcomeNames = outcomeNames;
        prop.launchThreshold = _threshold;
        prop.deadline = _deadline;
        prop.state = ProposalState.OPEN;
        prop.totalPerOutcome = new uint256[](outcomeNames.length);
        prop.year = year;
        prop.region = _toLowerCase(region);

        emit ProposalCreated(proposalId, questionId, "", year, prop.region, msg.sender, _threshold, _deadline);

        return proposalId;
    }

    // ========== COMMITMENT ==========

    function commit(bytes32 proposalId, uint256[] calldata amounts) external {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.OPEN) revert NotOpen();
        if (block.timestamp >= prop.deadline) revert DeadlinePassed();
        if (amounts.length != prop.outcomeNames.length) revert InvalidAmounts();

        _commit(proposalId, amounts);
    }

    function _commit(bytes32 proposalId, uint256[] calldata amounts) internal {
        ProposalStorage storage prop = proposals[proposalId];

        uint256 total;
        if (prop.committed[msg.sender].length == 0) {
            prop.committed[msg.sender] = new uint256[](amounts.length);
        }

        for (uint256 i; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;
            prop.committed[msg.sender][i] += amounts[i];
            prop.totalPerOutcome[i] += amounts[i];
            total += amounts[i];
        }
        if (total == 0) revert InvalidAmounts();

        if (!prop.hasCommitted[msg.sender]) {
            prop.committers.push(msg.sender);
            prop.hasCommitted[msg.sender] = true;
        }
        prop.totalCommitted += total;

        if (!usdc.transferFrom(msg.sender, address(this), total)) revert TransferFailed();

        emit Committed(proposalId, msg.sender, amounts, total);
    }

    // ========== LAUNCH ==========

    /**
     * @notice Launches a market once commitments reach the threshold. Callable by anyone.
     *         Must be called before the proposal deadline.
     *         Creation fee is pulled from feeSource. Share distribution deferred to claimShares().
     */
    function launchMarket(bytes32 proposalId) external {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.OPEN) revert NotOpen();
        if (block.timestamp >= prop.deadline) revert DeadlinePassed();
        if (prop.totalCommitted < prop.launchThreshold) revert BelowThreshold();

        prop.state = ProposalState.LAUNCHED;

        uint256 n = prop.outcomeNames.length;

        // 1. Pull creation fee from feeSource
        uint256 creationFee = predictionMarket.marketCreationFee() * n;
        if (!usdc.transferFrom(feeSource, address(this), creationFee)) revert TransferFailed();

        // 2. Create market
        int256[] memory zeroDelta = new int256[](n);
        string[] memory outcomeNames = prop.outcomeNames;

        PredictionMarket.CreateMarketParams memory params = PredictionMarket.CreateMarketParams({
            oracle: prop.oracle,
            initialBuyMaxCost: 0,
            questionId: prop.questionId,
            surplusRecipient: surplusRecipient,
            metadata: prop.metadata,
            initialBuyShares: zeroDelta,
            outcomeNames: outcomeNames
        });

        bytes32 marketId = predictionMarket.createMarket(params);
        prop.marketId = marketId;

        // 3. Binary search for aggregate trade
        PredictionMarket.MarketInfo memory info = predictionMarket.getMarketInfo(marketId);
        int256[] memory deltaShares = _computeAggregateShares(info, prop.totalPerOutcome, prop.totalCommitted);

        // 4. Execute aggregate trade
        uint256 actualCost;
        {
            bool hasNonZero;
            for (uint256 i; i < n; i++) {
                if (deltaShares[i] != 0) {
                    hasNonZero = true;
                    break;
                }
            }

            if (hasNonZero) {
                int256 costDelta = predictionMarket.trade(
                    PredictionMarket.Trade({
                        marketId: marketId,
                        deltaShares: deltaShares,
                        maxCost: prop.totalCommitted,
                        minPayout: 0,
                        deadline: block.timestamp
                    })
                );
                if (costDelta > 0) {
                    actualCost = uint256(costDelta);
                }
            }
        }

        // 5. Store results for lazy claimShares()
        prop.actualCost = actualCost;
        prop.totalSharesPerOutcome = new uint256[](n);
        for (uint256 i; i < n; i++) {
            if (deltaShares[i] > 0) {
                prop.totalSharesPerOutcome[i] = uint256(deltaShares[i]);
            }
        }

        emit MarketLaunched(proposalId, marketId, actualCost, prop.committers.length);
    }

    // ========== CLAIM SHARES ==========

    /**
     * @notice Claims outcome tokens and any USDC refund after launch.
     *         Tokens go directly to caller's wallet — no locking, trade freely.
     */
    function claimShares(bytes32 proposalId) external {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.LAUNCHED) revert NotLaunched();
        if (prop.claimed[msg.sender]) revert AlreadyClaimed();
        if (prop.committed[msg.sender].length == 0) revert NothingToClaim();

        prop.claimed[msg.sender] = true;

        bytes32 marketId = prop.marketId;
        PredictionMarket.MarketInfo memory mInfo = predictionMarket.getMarketInfo(marketId);
        uint256 n = prop.outcomeNames.length;

        uint256 userTotal;
        uint256[] memory userShares = new uint256[](n);

        for (uint256 i; i < n; i++) {
            uint256 userCommitted = prop.committed[msg.sender][i];
            userTotal += userCommitted;
            if (userCommitted == 0 || prop.totalPerOutcome[i] == 0 || prop.totalSharesPerOutcome[i] == 0) continue;
            userShares[i] = FixedPointMathLib.mulDiv(
                prop.totalSharesPerOutcome[i], userCommitted, prop.totalPerOutcome[i]
            );
        }

        for (uint256 i; i < n; i++) {
            if (userShares[i] > 0) {
                if (!IERC20(mInfo.outcomeTokens[i]).transfer(msg.sender, userShares[i])) revert TransferFailed();
            }
        }

        uint256 refund;
        uint256 unspent = prop.totalCommitted - prop.actualCost;
        if (unspent > 0 && userTotal > 0) {
            refund = FixedPointMathLib.mulDiv(unspent, userTotal, prop.totalCommitted);
            if (refund > 0) pendingRefunds[msg.sender] += refund;
        }

        emit SharesClaimed(proposalId, msg.sender, userShares, refund);
    }

    // ========== BINARY SEARCH ==========

    function _computeAggregateShares(
        PredictionMarket.MarketInfo memory info,
        uint256[] storage totalPerOutcome,
        uint256 totalCommitted
    ) internal view returns (int256[] memory deltaShares) {
        uint256 n = totalPerOutcome.length;
        deltaShares = new int256[](n);

        uint256 lo = 0;
        uint256 hi = 2e6;

        for (uint256 iter; iter < 64; iter++) {
            uint256 mid = (lo + hi) / 2;
            if (mid == lo) break;

            for (uint256 i; i < n; i++) {
                deltaShares[i] = int256(FixedPointMathLib.mulDiv(mid, totalPerOutcome[i], 1e6));
            }

            int256 quotedCost = predictionMarket.quoteTrade(info.outcomeQs, info.alpha, deltaShares);

            if (quotedCost <= int256(totalCommitted)) {
                lo = mid;
            } else {
                hi = mid;
            }
        }

        for (uint256 i; i < n; i++) {
            deltaShares[i] = int256(FixedPointMathLib.mulDiv(lo, totalPerOutcome[i], 1e6));
        }
    }

    // ========== WITHDRAWALS ==========

    function withdrawCommitment(bytes32 proposalId) external {
        ProposalStorage storage prop = proposals[proposalId];
        if (
            prop.state != ProposalState.EXPIRED && prop.state != ProposalState.CANCELLED
                && !(prop.state == ProposalState.OPEN && block.timestamp >= prop.deadline)
        ) {
            revert NotWithdrawable();
        }
        if (prop.state == ProposalState.OPEN) {
            prop.state = ProposalState.EXPIRED;
        }

        uint256 n = prop.outcomeNames.length;
        uint256 total;
        for (uint256 i; i < n; i++) {
            total += prop.committed[msg.sender][i];
            prop.committed[msg.sender][i] = 0;
        }
        if (total == 0) revert NothingToWithdraw();

        if (!usdc.transfer(msg.sender, total)) revert TransferFailed();
        emit CommitmentWithdrawn(proposalId, msg.sender, total);
    }

    function cancelProposal(bytes32 proposalId) external onlyOwner {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.OPEN) revert NotOpen();
        prop.state = ProposalState.CANCELLED;
        emit ProposalCancelled(proposalId);
    }

    function claimRefund() external {
        uint256 amount = pendingRefunds[msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingRefunds[msg.sender] = 0;
        if (!usdc.transfer(msg.sender, amount)) revert TransferFailed();
        emit RefundClaimed(msg.sender, amount);
    }

    // ========== VIEW ==========

    function getProposal(bytes32 proposalId) external view returns (ProposalInfo memory) {
        ProposalStorage storage prop = proposals[proposalId];
        return ProposalInfo({
            questionId: prop.questionId,
            oracle: prop.oracle,
            metadata: prop.metadata,
            outcomeNames: prop.outcomeNames,
            launchThreshold: prop.launchThreshold,
            deadline: prop.deadline,
            state: prop.state,
            marketId: prop.marketId,
            totalPerOutcome: prop.totalPerOutcome,
            totalCommitted: prop.totalCommitted,
            committers: prop.committers,
            name: prop.name,
            year: prop.year,
            region: prop.region,
            actualCost: prop.actualCost,
            totalSharesPerOutcome: prop.totalSharesPerOutcome
        });
    }

    function getCommitted(bytes32 proposalId, address user) external view returns (uint256[] memory) {
        return proposals[proposalId].committed[user];
    }

    function hasClaimed(bytes32 proposalId, address user) external view returns (bool) {
        return proposals[proposalId].claimed[user];
    }

    function getMarketKey(string calldata name, uint16 year, string calldata region) external pure returns (bytes32) {
        return keccak256(abi.encode(_toLowerCase(name), year, _toLowerCase(region)));
    }

    function getProposalByMarketKey(string calldata name, uint16 year, string calldata region)
        external
        view
        returns (bytes32)
    {
        bytes32 key = keccak256(abi.encode(_toLowerCase(name), year, _toLowerCase(region)));
        return marketKeyToProposal[key];
    }

    // ========== INTERNAL ==========

    function _toLowerCase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}
