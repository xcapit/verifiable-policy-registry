// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IPolicyRegistry {
    function scopes(bytes32 scopeId) external view returns (address governor, uint64 maxValidity, bool exists);
}

/// @title Metrics Anchor
/// @notice Anchors one Merkle root per scope per day. Each root commits to a public dataset of aggregated
///         counts with small cells suppressed (school id, day, category, count). Anyone can download the
///         dataset from `datasetUri`, recompute the root and compare it with the one anchored here, or verify
///         a single row on-chain with `verifyRow`.
/// @dev Dataset format 2. Leaves and internal nodes are domain-separated (0x00 / 0x01, as in RFC 9162), and
///      the leaf is computed here from the row itself, so a caller cannot present an internal node as a row
///      and a row cannot be verified against a different day. Roots are write-once. The publisher of a scope
///      is appointed by that scope's governor in the policy registry; there is no first-caller configuration.
contract MetricsAnchor {
    struct Commitment {
        bytes32 root;
        string datasetUri;
        uint64 committedAt;
    }

    IPolicyRegistry public immutable registry;

    /// @notice Address allowed to anchor roots for each scope (the operator of the resolver).
    mapping(bytes32 => address) public publisher;
    mapping(bytes32 => mapping(uint32 => Commitment)) private _commitments;

    event PublisherSet(bytes32 indexed scopeId, address indexed governor, address indexed publisher);
    event RootCommitted(bytes32 indexed scopeId, uint32 indexed day, bytes32 root, string datasetUri);

    error UnknownScope();
    error NotGovernor();
    error NotPublisher();
    error DayAlreadyCommitted();
    error EmptyRoot();
    error ZeroAddress();
    error FieldTooLong();

    constructor(IPolicyRegistry policyRegistry) {
        if (address(policyRegistry) == address(0)) revert ZeroAddress();
        registry = policyRegistry;
    }

    /// @notice Appoint or rotate the publisher of a scope. Only the scope's current governor in the registry
    ///         can do this, so a scope cannot be claimed by whoever calls first.
    function setPublisher(bytes32 scopeId, address newPublisher) external {
        (address governor,, bool exists) = registry.scopes(scopeId);
        if (!exists) revert UnknownScope();
        if (msg.sender != governor) revert NotGovernor();
        if (newPublisher == address(0)) revert ZeroAddress();
        publisher[scopeId] = newPublisher;
        emit PublisherSet(scopeId, governor, newPublisher);
    }

    /// @param day Days since the Unix epoch (UTC).
    function commitRoot(bytes32 scopeId, uint32 day, bytes32 root, string calldata datasetUri) external {
        if (msg.sender != publisher[scopeId] || msg.sender == address(0)) revert NotPublisher();
        if (root == bytes32(0)) revert EmptyRoot();
        if (_commitments[scopeId][day].root != bytes32(0)) revert DayAlreadyCommitted();
        _commitments[scopeId][day] = Commitment({root: root, datasetUri: datasetUri, committedAt: uint64(block.timestamp)});
        emit RootCommitted(scopeId, day, root, datasetUri);
    }

    function getCommitment(bytes32 scopeId, uint32 day) external view returns (Commitment memory) {
        return _commitments[scopeId][day];
    }

    /// @notice Leaf of a dataset row (format 2): keccak256(0x00 ‖ day ‖ count ‖ len(school) ‖ school ‖ len(category) ‖ category),
    ///         with day as uint32, count as uint256 and lengths as uint16, all big-endian.
    function leafHash(uint32 day, string calldata schoolId, string calldata category, uint256 count)
        public
        pure
        returns (bytes32)
    {
        if (bytes(schoolId).length > type(uint16).max || bytes(category).length > type(uint16).max) {
            revert FieldTooLong();
        }
        return keccak256(
            abi.encodePacked(
                bytes1(0x00),
                day,
                count,
                uint16(bytes(schoolId).length),
                schoolId,
                uint16(bytes(category).length),
                category
            )
        );
    }

    /// @notice Verify that a row belongs to the dataset anchored for (scope, day). The leaf is computed from the
    ///         row and the anchored day, and internal nodes are keccak256(0x01 ‖ min(a, b) ‖ max(a, b)).
    function verifyRow(
        bytes32 scopeId,
        uint32 day,
        string calldata schoolId,
        string calldata category,
        uint256 count,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 computed = leafHash(day, schoolId, category, count);
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
