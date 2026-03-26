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
 *         Anyone can propose a market for a name in the Merkle tree and commit capital.
 *         Once commitments cross the launch threshold, anyone can trigger market creation.
 *         All committed trades execute simultaneously at the same initial 50/50 prices.
 */
contract Vault is OwnableRoles {
    PredictionMarket public predictionMarket;
    IERC20 public usdc;

    // ========== NAME VALIDATION ==========

    /// @notice Merkle root of valid SSA names (0 = no whitelist enforced, all names allowed)
    bytes32 public namesMerkleRoot;

    /// @notice Names manually approved by owner (keccak256(lowercased) => true)
    mapping(bytes32 => bool) public approvedNames;

    // ========== DEFAULT MARKET PARAMS ==========

    /// @notice Default oracle address for new proposals
    address public defaultOracle;

    /// @notice Default minimum USDC commitment to trigger market launch
    uint256 public defaultLaunchThreshold;

    /// @notice Default proposal duration in seconds (added to block.timestamp at propose time)
    uint256 public defaultDeadlineDuration;

    /// @notice Surplus recipient for all markets created by this Vault
    address public surplusRecipient;

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
        mapping(address => uint256[]) committed;
        mapping(address => bool) hasCommitted;
    }

    mapping(bytes32 => ProposalStorage) internal proposals;

    /// @notice Maps name hash to proposalId to prevent duplicate proposals for the same name
    mapping(bytes32 => bytes32) public nameToProposal;

    // marketId => user => locked share amounts per outcome
    mapping(bytes32 => mapping(address => uint256[])) public locked;

    // Pending USDC refunds from launch overpayment
    mapping(address => uint256) public pendingRefunds;

    // ========== EVENTS ==========

    event ProposalCreated(
        bytes32 indexed proposalId,
        bytes32 indexed questionId,
        string name,
        address proposer,
        uint256 launchThreshold,
        uint256 deadline
    );
    event Committed(bytes32 indexed proposalId, address indexed user, uint256[] amounts, uint256 total);
    event CommitmentWithdrawn(bytes32 indexed proposalId, address indexed user, uint256 amount);
    event MarketLaunched(
        bytes32 indexed proposalId, bytes32 indexed marketId, uint256 actualCost, uint256 committerCount
    );
    event ProposalCancelled(bytes32 indexed proposalId);
    event RefundClaimed(address indexed user, uint256 amount);
    event Unlocked(bytes32 indexed marketId, address indexed user, uint256[] amounts);
    event SurplusRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event NamesMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event NameApproved(string name);
    event DefaultOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DefaultLaunchThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event DefaultDeadlineDurationUpdated(uint256 oldDuration, uint256 newDuration);

    // ========== ERRORS ==========

    error NotOpen();
    error DeadlinePassed();
    error InvalidAmounts();
    error ProposalExists();
    error DuplicateName();
    error InvalidDeadline();
    error InvalidThreshold();
    error InvalidOracle();
    error InvalidOutcomes();
    error InvalidName();
    error BelowThreshold();
    error NotWithdrawable();
    error NothingToWithdraw();
    error NothingToClaim();
    error NoLockedTokens();
    error MarketNotResolved();
    error TransferFailed();
    error ZeroAddress();
    error InsufficientVaultBalance();
    error DefaultsNotSet();

    constructor(
        address _predictionMarket,
        address _surplusRecipient,
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

        if (_defaultOracle == address(0)) revert InvalidOracle();
        defaultOracle = _defaultOracle;
        emit DefaultOracleUpdated(address(0), _defaultOracle);

        defaultLaunchThreshold = _defaultLaunchThreshold;
        emit DefaultLaunchThresholdUpdated(0, _defaultLaunchThreshold);

        defaultDeadlineDuration = _defaultDeadlineDuration;
        emit DefaultDeadlineDurationUpdated(0, _defaultDeadlineDuration);

        usdc.approve(_predictionMarket, type(uint256).max);
    }

    // ========== ADMIN ==========

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

    /**
     * @notice Validates a name against the Merkle tree or manual approval list
     * @dev Uses double-hash leaf format matching OZ StandardMerkleTree:
     *      leaf = keccak256(keccak256(abi.encode(lowercasedName)))
     */
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
     *         Callable by anyone. Name must be valid per Merkle tree or approval list.
     *         Creates a binary market proposal (YES/NO) using default parameters.
     * @param name The baby name to create a market for
     * @param proof Merkle proof that the name is in the valid names tree
     * @param amounts Commitment amounts per outcome (length must match outcome count = 2)
     * @return proposalId The unique proposal identifier
     */
    function propose(string calldata name, bytes32[] calldata proof, uint256[] calldata amounts)
        external
        returns (bytes32)
    {
        if (!isValidName(name, proof)) revert InvalidName();
        if (defaultOracle == address(0)) revert DefaultsNotSet();
        if (defaultDeadlineDuration == 0) revert DefaultsNotSet();
        if (defaultLaunchThreshold == 0) revert DefaultsNotSet();

        string memory lowered = _toLowerCase(name);
        bytes32 nameHash = keccak256(bytes(lowered));

        // Prevent duplicate proposals for the same name
        if (nameToProposal[nameHash] != bytes32(0)) {
            bytes32 existingId = nameToProposal[nameHash];
            ProposalStorage storage existing = proposals[existingId];
            if (existing.state == ProposalState.OPEN && block.timestamp < existing.deadline) {
                revert DuplicateName();
            }
        }

        // Build questionId: first 20 bytes = vault address, last 12 bytes = name hash truncated
        bytes32 questionId = bytes32(
            (uint256(uint160(address(this))) << 96) | uint256(uint96(bytes12(nameHash)))
        );

        bytes32 proposalId =
            keccak256(abi.encodePacked(address(this), block.chainid, questionId, block.timestamp));
        if (proposals[proposalId].deadline != 0) revert ProposalExists();

        // Binary market: YES / NO
        string[] memory outcomeNames = new string[](2);
        outcomeNames[0] = "YES";
        outcomeNames[1] = "NO";

        uint256 deadline = block.timestamp + defaultDeadlineDuration;

        ProposalStorage storage prop = proposals[proposalId];
        prop.questionId = questionId;
        prop.oracle = defaultOracle;
        prop.metadata = abi.encode(lowered);
        prop.outcomeNames = outcomeNames;
        prop.launchThreshold = defaultLaunchThreshold;
        prop.deadline = deadline;
        prop.state = ProposalState.OPEN;
        prop.totalPerOutcome = new uint256[](2);
        prop.name = lowered;

        nameToProposal[nameHash] = proposalId;

        emit ProposalCreated(proposalId, questionId, lowered, msg.sender, defaultLaunchThreshold, deadline);

        // Commit in the same call
        if (amounts.length != 2) revert InvalidAmounts();
        _commit(proposalId, amounts);

        return proposalId;
    }

    /**
     * @notice Admin creates a proposal with custom parameters, bypassing name validation.
     *         Use for non-name markets or markets that don't fit the standard binary template.
     *         Markets are resolved manually by the oracle — typically when the SSA report
     *         is published (expected around Mother's Day, but actual timing varies).
     * @param outcomeNames Array of outcome names (e.g. ["YES","NO"] or custom)
     * @param oracle Address that will resolve the market (can pauseMarket/unpauseMarket while waiting for data)
     * @param metadata Arbitrary metadata bytes
     * @param launchThreshold Minimum USDC commitment to trigger launch (0 = use default)
     * @param deadline Unix timestamp when proposal expires (0 = use default duration)
     * @return proposalId The unique proposal identifier
     */
    function adminPropose(
        string[] calldata outcomeNames,
        address oracle,
        bytes calldata metadata,
        uint256 launchThreshold,
        uint256 deadline
    ) external onlyOwner returns (bytes32) {
        if (outcomeNames.length < 2) revert InvalidOutcomes();
        if (oracle == address(0)) revert InvalidOracle();

        uint256 _threshold = launchThreshold > 0 ? launchThreshold : defaultLaunchThreshold;
        uint256 _deadline = deadline > 0 ? deadline : block.timestamp + defaultDeadlineDuration;
        if (_threshold == 0) revert InvalidThreshold();
        if (_deadline <= block.timestamp) revert InvalidDeadline();

        // Build questionId: first 20 bytes = vault address, last 12 bytes from metadata hash
        bytes32 metaHash = keccak256(metadata);
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

        emit ProposalCreated(proposalId, questionId, "", msg.sender, _threshold, _deadline);

        return proposalId;
    }

    /**
     * @notice Commits USDC to one or more outcomes of an open proposal.
     *         Callable multiple times; amounts accumulate.
     */
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

    /**
     * @notice Launches a market once commitments reach the threshold. Callable by anyone.
     *         Pays the creation fee from Vault balance, creates the market, then executes
     *         all committed trades at the same initial prices via a single aggregate trade.
     */
    function launchMarket(bytes32 proposalId) external {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.OPEN) revert NotOpen();
        if (prop.totalCommitted < prop.launchThreshold) revert BelowThreshold();

        prop.state = ProposalState.LAUNCHED;

        uint256 n = prop.outcomeNames.length;

        // 1. Create the market. Vault pays the creation fee from its own balance.
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

        // 2. Compute aggregate deltaShares via binary search
        PredictionMarket.MarketInfo memory info = predictionMarket.getMarketInfo(marketId);

        int256[] memory deltaShares = _computeAggregateShares(info, prop.totalPerOutcome, prop.totalCommitted);

        // 3. Execute the single aggregate trade
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

        // 4. Record proportional refunds for any unspent USDC
        uint256 unspent = prop.totalCommitted - actualCost;

        // 5. Lock tokens for each committer proportionally
        uint256[] memory totalSharesPerOutcome = new uint256[](n);
        for (uint256 i; i < n; i++) {
            if (deltaShares[i] > 0) {
                totalSharesPerOutcome[i] = uint256(deltaShares[i]);
            }
        }

        for (uint256 u; u < prop.committers.length; u++) {
            address committer = prop.committers[u];
            if (locked[marketId][committer].length == 0) {
                locked[marketId][committer] = new uint256[](n);
            }
            uint256 userTotal;
            for (uint256 i; i < n; i++) {
                uint256 userCommitted = prop.committed[committer][i];
                if (userCommitted == 0) continue;
                userTotal += userCommitted;
                if (prop.totalPerOutcome[i] == 0) continue;
                if (totalSharesPerOutcome[i] == 0) continue;
                uint256 userShares = FixedPointMathLib.mulDiv(
                    totalSharesPerOutcome[i], userCommitted, prop.totalPerOutcome[i]
                );
                locked[marketId][committer][i] += userShares;
            }
            if (unspent > 0 && userTotal > 0) {
                uint256 refund = FixedPointMathLib.mulDiv(unspent, userTotal, prop.totalCommitted);
                if (refund > 0) pendingRefunds[committer] += refund;
            }
        }

        emit MarketLaunched(proposalId, marketId, actualCost, prop.committers.length);
    }

    /**
     * @notice Computes aggregate deltaShares via binary search such that
     *         the total LMSR cost does not exceed totalCommitted.
     */
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

    /**
     * @notice Withdraws committed USDC if proposal expired or was cancelled
     */
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

    /**
     * @notice Cancels an open proposal. Only callable by owner.
     */
    function cancelProposal(bytes32 proposalId) external onlyOwner {
        ProposalStorage storage prop = proposals[proposalId];
        if (prop.state != ProposalState.OPEN) revert NotOpen();
        prop.state = ProposalState.CANCELLED;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Claims any pending USDC refund from unspent launch capital
     */
    function claimRefund() external {
        uint256 amount = pendingRefunds[msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingRefunds[msg.sender] = 0;
        if (!usdc.transfer(msg.sender, amount)) revert TransferFailed();
        emit RefundClaimed(msg.sender, amount);
    }

    // ========== UNLOCK ==========

    /**
     * @notice Unlocks and returns all locked outcome tokens after market resolution.
     *         Users then call redeem() on PredictionMarket directly.
     */
    function unlock(bytes32 marketId) external {
        uint256[] storage lock = locked[marketId][msg.sender];
        if (lock.length == 0) revert NoLockedTokens();

        PredictionMarket.MarketInfo memory m = predictionMarket.getMarketInfo(marketId);
        if (!m.resolved) revert MarketNotResolved();

        uint256[] memory amounts = new uint256[](lock.length);
        for (uint256 i; i < lock.length; i++) {
            amounts[i] = lock[i];
        }
        delete locked[marketId][msg.sender];

        for (uint256 i; i < amounts.length; i++) {
            if (amounts[i] > 0) {
                if (!IERC20(m.outcomeTokens[i]).transfer(msg.sender, amounts[i])) revert TransferFailed();
            }
        }

        emit Unlocked(marketId, msg.sender, amounts);
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
            name: prop.name
        });
    }

    function getCommitted(bytes32 proposalId, address user) external view returns (uint256[] memory) {
        return proposals[proposalId].committed[user];
    }

    function getLocked(bytes32 marketId, address user) external view returns (uint256[] memory) {
        return locked[marketId][user];
    }

    function getProposalByName(string calldata name) external view returns (bytes32) {
        string memory lowered = _toLowerCase(name);
        bytes32 nameHash = keccak256(bytes(lowered));
        return nameToProposal[nameHash];
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
