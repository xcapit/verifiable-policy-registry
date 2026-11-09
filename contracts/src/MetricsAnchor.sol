// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IPolicyRegistry {
    function scopes(bytes32 scopeId) external view returns (address governor, uint64 maxValidity, bool exists);
}

/// @title Metrics Anchor
/// @notice Anchors one Merkle root per scope per day. Each root commits to a public dataset of aggregated
///         counts with small cells suppressed (unit id, day, category, count). Anyone can download the dataset
///         from `datasetUri`, recompute the root and compare it with the one anchored here, or verify a single
///         row on-chain with `verifyRow`.
/// @dev Dataset format 2: leaves and internal nodes are domain-separated (0x00 / 0x01), the leaf is computed
///      here from the row itself, and it binds the anchored day.
///      - The publisher of a scope is appointed, rotated or revoked by that scope's current governor in the
///        registry. A governor rotation does not revoke the publisher automatically; the new governor should.
///      - A publisher can anchor a day once, never a future day, and, if the governor set a lag limit, not a day
///        older than that limit. A day with nothing to publish is marked empty, so a gap is never ambiguous.
///      - Only the governor can correct an anchored root. Corrections are public, carry a reason hash and
///        increment a revision counter; the original root remains visible in the events.
contract MetricsAnchor {
    uint256 public constant MAX_URI_LENGTH = 256;

    struct Commitment {
        bytes32 root;
        string datasetUri;
        uint64 committedAt;
        uint32 revision; // 0 for the original commitment, incremented by each correction
        bool empty; // the publisher declared that nothing was publishable that day
    }

    IPolicyRegistry public immutable registry;

    /// @notice Address allowed to anchor roots for each scope (the operator of the resolver); zero if none.
    mapping(bytes32 => address) public publisher;
    /// @notice Maximum age, in days, of a day the publisher may still anchor; 0 means no limit.
    mapping(bytes32 => uint32) public maxLagDays;
    mapping(bytes32 => mapping(uint32 => Commitment)) private _commitments;

    event PublisherSet(bytes32 indexed scopeId, address indexed governor, address indexed publisher, uint32 maxLagDays);
    event RootCommitted(bytes32 indexed scopeId, uint32 indexed day, bytes32 root, string datasetUri);
    event EmptyDayMarked(bytes32 indexed scopeId, uint32 indexed day);
    event RootCorrected(
        bytes32 indexed scopeId, uint32 indexed day, bytes32 previousRoot, bytes32 newRoot, bytes32 reasonHash, uint32 revision
    );

    error UnknownScope();
    error NotGovernor();
    error NotPublisher();
    error DayAlreadyCommitted();
    error DayNotCommitted();
    error DayInFuture();
    error DayTooOld();
    error EmptyRoot();
    error EmptyReason();
    error ZeroAddress();
    error FieldTooLong();
    error UriTooLong();

    constructor(IPolicyRegistry policyRegistry) {
        if (address(policyRegistry) == address(0)) revert ZeroAddress();
        registry = policyRegistry;
    }

    function _governor(bytes32 scopeId) private view returns (address governor) {
        bool exists;
        (governor,, exists) = registry.scopes(scopeId);
        if (!exists) revert UnknownScope();
    }

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    /// @notice Appoint, rotate or revoke (address(0)) the publisher of a scope, and set the back-fill limit.
    ///         Only the scope's current governor in the registry can do this.
    function setPublisher(bytes32 scopeId, address newPublisher, uint32 lagDays) external {
        address governor = _governor(scopeId);
        if (msg.sender != governor) revert NotGovernor();
        publisher[scopeId] = newPublisher;
        maxLagDays[scopeId] = lagDays;
        emit PublisherSet(scopeId, governor, newPublisher, lagDays);
    }

    function _checkPublishable(bytes32 scopeId, uint32 day) private view {
        if (msg.sender != publisher[scopeId] || msg.sender == address(0)) revert NotPublisher();
        uint32 t = today();
        if (day > t) revert DayInFuture();
        uint32 lag = maxLagDays[scopeId];
        if (lag != 0 && uint256(day) + lag < t) revert DayTooOld();
        if (_commitments[scopeId][day].committedAt != 0) revert DayAlreadyCommitted();
    }

    /// @param day Days since the Unix epoch (UTC).
    function commitRoot(bytes32 scopeId, uint32 day, bytes32 root, string calldata datasetUri) external {
        _checkPublishable(scopeId, day);
        if (root == bytes32(0)) revert EmptyRoot();
        if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();
        _commitments[scopeId][day] =
            Commitment({root: root, datasetUri: datasetUri, committedAt: uint64(block.timestamp), revision: 0, empty: false});
        emit RootCommitted(scopeId, day, root, datasetUri);
    }

    /// @notice Declare that a day had no publishable cell, so that the absence of a root is not ambiguous.
    function markEmpty(bytes32 scopeId, uint32 day) external {
        _checkPublishable(scopeId, day);
        _commitments[scopeId][day] =
            Commitment({root: bytes32(0), datasetUri: "", committedAt: uint64(block.timestamp), revision: 0, empty: true});
        emit EmptyDayMarked(scopeId, day);
    }

    /// @notice Governor-authorised correction of an anchored day, with the hash of a published reason.
    function correctRoot(bytes32 scopeId, uint32 day, bytes32 newRoot, string calldata datasetUri, bytes32 reasonHash)
        external
    {
        if (msg.sender != _governor(scopeId)) revert NotGovernor();
        Commitment storage c = _commitments[scopeId][day];
        if (c.committedAt == 0) revert DayNotCommitted();
        if (newRoot == bytes32(0)) revert EmptyRoot();
        if (reasonHash == bytes32(0)) revert EmptyReason();
        if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();
        bytes32 previous = c.root;
        c.root = newRoot;
        c.datasetUri = datasetUri;
        c.empty = false;
        c.revision += 1;
        emit RootCorrected(scopeId, day, previous, newRoot, reasonHash, c.revision);
    }

    function getCommitment(bytes32 scopeId, uint32 day) external view returns (Commitment memory) {
        return _commitments[scopeId][day];
    }

    /// @notice Leaf of a dataset row (format 2): keccak256(0x00 ‖ day ‖ count ‖ len(unit) ‖ unit ‖ len(category) ‖ category),
    ///         with day as uint32, count as uint256 and lengths as uint16, all big-endian.
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
    ///         from the row and the anchored day; internal nodes are keccak256(0x01 ‖ min(a, b) ‖ max(a, b)).
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
