// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

/// @notice The part of the policy registry the anchor reads: the governor of a scope and whether it exists.
interface IPolicyRegistry {
    /// @param scopeId Scope identifier.
    /// @return governor Current governor of the scope.
    /// @return maxValidity Maximum lifetime of a policy version in the scope, in seconds.
    /// @return exists Whether the scope has been created.
    function scopes(bytes32 scopeId) external view returns (address governor, uint64 maxValidity, bool exists);
}

/// @title Metrics Anchor
/// @author Xcapit (dpg@xcapit.com)
/// @notice Anchors one Merkle root per scope per day. Each root commits to a public release of aggregated
///         counts (unit id, day, category, count) with small cells suppressed. Anyone can recompute the root
///         from the release at `datasetUri`, or check a single row on-chain with `verifyRow`.
/// @dev Encoding (dataset format 2, docs/INTERFACES.md I6). leaf = keccak256(0x00 || day || count || len(unit) ||
///      unit || len(category) || category); node = keccak256(0x01 || min(a, b) || max(a, b)). The leaf is
///      computed here from the row, so an internal node cannot pass as a row, and it binds the day. It does
///      not bind the scope: roots are stored per scope and a row is checked only against its own scope's root.
///      Roles. The scope's current governor in the registry appoints, rotates or revokes the publisher; a
///      governor handover does not revoke it. The publisher writes each (scope, day) once, after the UTC day
///      has ended and within `maxLagDays`, and marks a day with nothing to publish as empty. Only the governor
///      corrects a written day, with a reason hash; each correction increments `revision`.
///      Time. Day numbers follow UTC to about +/-30 minutes on OP Stack, so a day can be anchored up to about
///      30 minutes before it ends in real time, and the sequencer can delay a write across a day boundary
///      (docs/security/CONTRACT_ASSURANCE.md section 9).
///      Invariants: test-foundry/AnchorInvariants.t.sol. Holds no funds, is not upgradeable, and makes one
///      external call, a view to the registry.
contract MetricsAnchor {
    /// @notice Maximum length, in bytes, of a dataset URI written on-chain.
    uint256 public constant MAX_URI_LENGTH = 256;
    /// @notice `maxLagDays` value that disables the back-fill bound.
    uint32 public constant NO_LAG_LIMIT = type(uint32).max;

    /// @notice What is stored for one (scope, day).
    struct Commitment {
        bytes32 root; // Merkle root of the release; 0 if and only if the day is empty
        string datasetUri; // where the release is published (at most MAX_URI_LENGTH bytes)
        uint64 committedAt; // timestamp of the publisher's original write; corrections do not change it
        uint32 revision; // 0 for the original write, incremented by each governor correction
        bool empty; // nothing was publishable that day
    }

    /// @notice The policy registry whose governors control each scope.
    IPolicyRegistry public immutable registry;

    /// @notice Address allowed to anchor roots for each scope (the operator of the resolver); zero if none.
    mapping(bytes32 => address) public publisher;
    /// @notice Maximum number of days after a day ends during which the publisher may still anchor it;
    ///         NO_LAG_LIMIT for no bound. Always at least 1 while a publisher is appointed, 0 when revoked.
    mapping(bytes32 => uint32) public maxLagDays;
    mapping(bytes32 => mapping(uint32 => Commitment)) private _commitments;

    /// @notice The governor appointed, rotated or revoked (address(0)) the publisher of a scope.
    event PublisherSet(bytes32 indexed scopeId, address indexed governor, address indexed publisher, uint32 maxLagDays);
    /// @notice The publisher anchored the root of a day's release.
    event RootCommitted(bytes32 indexed scopeId, uint32 indexed day, bytes32 root, string datasetUri);
    /// @notice The publisher declared that a day had no publishable cell.
    event EmptyDayMarked(bytes32 indexed scopeId, uint32 indexed day);
    /// @notice The governor corrected a day. `previousRoot` or `newRoot` equal to 0 means an empty day.
    event RootCorrected(
        bytes32 indexed scopeId,
        uint32 indexed day,
        bytes32 previousRoot,
        bytes32 newRoot,
        string datasetUri,
        bytes32 reasonHash,
        uint32 revision
    );

    /// @notice The scope does not exist in the registry.
    error UnknownScope();
    /// @notice The caller is not the scope's current governor.
    error NotGovernor();
    /// @notice The caller is not the scope's publisher.
    error NotPublisher();
    /// @notice The day has already been anchored or marked empty.
    error DayAlreadyCommitted();
    /// @notice The day has never been anchored or marked empty, so there is nothing to correct.
    error DayNotCommitted();
    /// @notice The UTC day has not ended yet.
    error DayNotClosed();
    /// @notice The day is older than the scope's back-fill window.
    error DayTooOld();
    /// @notice A publisher needs a lag of at least 1; a revocation needs a lag of 0.
    error InvalidLag();
    /// @notice The correction would leave the root unchanged.
    error NoChange();
    /// @notice An anchored root cannot be 0 (use markEmpty).
    error EmptyRoot();
    /// @notice A correction must carry the hash of a published reason.
    error EmptyReason();
    /// @notice The registry address is zero.
    error ZeroAddress();
    /// @notice A unit id or category is longer than 65 535 bytes, the limit of its length prefix.
    error FieldTooLong();
    /// @notice The dataset URI is longer than MAX_URI_LENGTH bytes.
    error UriTooLong();

    /// @param policyRegistry The VerifiablePolicyRegistry whose governors control each scope.
    constructor(IPolicyRegistry policyRegistry) {
        if (address(policyRegistry) == address(0)) revert ZeroAddress();
        registry = policyRegistry;
    }

    function _governor(bytes32 scopeId) private view returns (address governor) {
        bool exists;
        // slither-disable-next-line unused-return
        (governor,, exists) = registry.scopes(scopeId); // maxValidity is not needed here
        if (!exists) revert UnknownScope();
    }

    /// @notice Current UTC day number (days since 1970-01-01).
    /// @return The day number of the current block.
    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    /// @notice Appoint, rotate or revoke the publisher of a scope, and set its back-fill window. Only the scope's
    ///         current governor in the registry can do this.
    /// @param scopeId Scope identifier in the registry.
    /// @param newPublisher The new publisher, or address(0) to revoke.
    /// @param lagDays Back-fill window in days: at least 1 for a publisher (NO_LAG_LIMIT for no bound), 0 to revoke.
    function setPublisher(bytes32 scopeId, address newPublisher, uint32 lagDays) external {
        address governor = _governor(scopeId);
        if (msg.sender != governor) revert NotGovernor();
        if ((newPublisher == address(0)) != (lagDays == 0)) revert InvalidLag();
        publisher[scopeId] = newPublisher;
        maxLagDays[scopeId] = lagDays;
        emit PublisherSet(scopeId, governor, newPublisher, lagDays);
    }

    /// @dev Common checks for a publisher write. The comparisons use block.timestamp at day granularity on
    ///      purpose (see the contract-level note on OP Stack time).
    // slither-disable-next-line timestamp
    function _checkPublishable(bytes32 scopeId, uint32 day) private view {
        if (msg.sender != publisher[scopeId]) revert NotPublisher();
        uint32 t = today();
        if (day >= t) revert DayNotClosed();
        uint32 lag = maxLagDays[scopeId];
        if (lag != NO_LAG_LIMIT && uint256(day) + lag < t) revert DayTooOld();
        if (_commitments[scopeId][day].committedAt != 0) revert DayAlreadyCommitted();
    }

    /// @notice Anchor the root of a day's release. Publisher only, once per day, after the day has ended and
    ///         within the back-fill window.
    /// @param scopeId Scope identifier in the registry.
    /// @param day Days since the Unix epoch (UTC).
    /// @param root Merkle root of the release (dataset format 2); must not be 0.
    /// @param datasetUri Where the release is published; at most MAX_URI_LENGTH bytes.
    function commitRoot(bytes32 scopeId, uint32 day, bytes32 root, string calldata datasetUri) external {
        _checkPublishable(scopeId, day);
        if (root == bytes32(0)) revert EmptyRoot();
        if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();
        _commitments[scopeId][day] =
            Commitment({root: root, datasetUri: datasetUri, committedAt: uint64(block.timestamp), revision: 0, empty: false});
        emit RootCommitted(scopeId, day, root, datasetUri);
    }

    /// @notice Declare that a day had no publishable cell, so that the absence of a root is not ambiguous.
    ///         Same rules as commitRoot.
    /// @param scopeId Scope identifier in the registry.
    /// @param day Days since the Unix epoch (UTC).
    function markEmpty(bytes32 scopeId, uint32 day) external {
        _checkPublishable(scopeId, day);
        _commitments[scopeId][day] =
            Commitment({root: bytes32(0), datasetUri: "", committedAt: uint64(block.timestamp), revision: 0, empty: true});
        emit EmptyDayMarked(scopeId, day);
    }

    /// @notice Governor-authorised correction of an anchored or empty day, with the hash of a published reason.
    /// @param scopeId Scope identifier in the registry.
    /// @param day The day to correct; it must have been anchored or marked empty.
    /// @param newRoot The corrected root, or 0 to turn the day into an empty day; must differ from the current root.
    /// @param datasetUri Where the corrected release (or the correction note) is published.
    /// @param reasonHash Hash of the published reason for the correction; must not be 0.
    function correctRoot(bytes32 scopeId, uint32 day, bytes32 newRoot, string calldata datasetUri, bytes32 reasonHash)
        external
    {
        if (msg.sender != _governor(scopeId)) revert NotGovernor();
        Commitment storage c = _commitments[scopeId][day];
        if (c.committedAt == 0) revert DayNotCommitted();
        if (newRoot == c.root) revert NoChange();
        if (reasonHash == bytes32(0)) revert EmptyReason();
        if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();
        bytes32 previous = c.root;
        c.root = newRoot;
        c.datasetUri = datasetUri;
        c.empty = newRoot == bytes32(0);
        c.revision += 1;
        emit RootCorrected(scopeId, day, previous, newRoot, datasetUri, reasonHash, c.revision);
    }

    /// @notice The stored commitment for (scope, day); all fields are zero if the day was never written.
    /// @param scopeId Scope identifier in the registry.
    /// @param day Days since the Unix epoch (UTC).
    /// @return The commitment.
    function getCommitment(bytes32 scopeId, uint32 day) external view returns (Commitment memory) {
        return _commitments[scopeId][day];
    }

    /// @notice Leaf of a dataset row (format 2):
    ///         keccak256(0x00 || day || count || len(unit) || unit || len(category) || category),
    ///         with day as uint32, count as uint256 and lengths as uint16, all big-endian.
    /// @param day Days since the Unix epoch (UTC).
    /// @param unitId Unit identifier (the school id in the school use case), UTF-8.
    /// @param category Category name, UTF-8.
    /// @param count Number of events in the cell.
    /// @return The leaf hash.
    function leafHash(uint32 day, string calldata unitId, string calldata category, uint256 count)
        public
        pure
        returns (bytes32)
    {
        if (bytes(unitId).length > type(uint16).max || bytes(category).length > type(uint16).max) {
            revert FieldTooLong();
        }
        return keccak256(
            abi.encodePacked(
                bytes1(0x00), day, count, uint16(bytes(unitId).length), unitId, uint16(bytes(category).length), category
            )
        );
    }

    /// @notice Verify that a row belongs to the dataset currently anchored for (scope, day). The leaf is computed
    ///         from the row and the anchored day; internal nodes are keccak256(0x01 || min(a, b) || max(a, b)).
    /// @dev Proof length is not bounded here; a caller pays for its own proof. Returns false for an empty or
    ///      unanchored day.
    /// @param scopeId Scope identifier in the registry.
    /// @param day Days since the Unix epoch (UTC).
    /// @param unitId Unit identifier of the row.
    /// @param category Category of the row.
    /// @param count Count of the row.
    /// @param proof Sibling hashes from the leaf to the root.
    /// @return True if the row is in the anchored release.
    function verifyRow(
        bytes32 scopeId,
        uint32 day,
        string calldata unitId,
        string calldata category,
        uint256 count,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 computed = leafHash(day, unitId, category, count);
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            computed = computed < p
                ? keccak256(abi.encodePacked(bytes1(0x01), computed, p))
                : keccak256(abi.encodePacked(bytes1(0x01), p, computed));
        }
        bytes32 root = _commitments[scopeId][day].root;
        return root != bytes32(0) && computed == root;
    }
}
