// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @title Metrics Anchor
/// @notice Anchors one Merkle root per scope per day. Each root commits to a public dataset of aggregated,
///         k-anonymous counts (school id, day, category, count). Anyone can download the dataset from
///         `datasetUri`, recompute the root and compare it with the one anchored here.
/// @dev Roots are write-once: a published day can never be overwritten.
contract MetricsAnchor {
    struct Commitment {
        bytes32 root;
        string datasetUri;
        uint64 committedAt;
    }

    /// @notice Address allowed to anchor roots for each scope (the operator of the resolver).
    mapping(bytes32 => address) public publisher;
    /// @notice Address that can rotate the publisher (expected: the scope's governance Safe).
    mapping(bytes32 => address) public admin;
    mapping(bytes32 => mapping(uint32 => Commitment)) private _commitments;

    event PublisherSet(bytes32 indexed scopeId, address indexed admin, address indexed publisher);
    event RootCommitted(bytes32 indexed scopeId, uint32 indexed day, bytes32 root, string datasetUri);

    error AlreadyConfigured();
    error NotAdmin();
    error NotPublisher();
    error DayAlreadyCommitted();
    error EmptyRoot();
    error ZeroAddress();

    /// @notice One-time setup of a scope's admin and publisher.
    function configure(bytes32 scopeId, address scopeAdmin, address scopePublisher) external {
        if (admin[scopeId] != address(0)) revert AlreadyConfigured();
        if (scopeAdmin == address(0) || scopePublisher == address(0)) revert ZeroAddress();
        admin[scopeId] = scopeAdmin;
        publisher[scopeId] = scopePublisher;
        emit PublisherSet(scopeId, scopeAdmin, scopePublisher);
    }

    function setPublisher(bytes32 scopeId, address newPublisher) external {
        if (msg.sender != admin[scopeId]) revert NotAdmin();
        if (newPublisher == address(0)) revert ZeroAddress();
        publisher[scopeId] = newPublisher;
        emit PublisherSet(scopeId, msg.sender, newPublisher);
    }

    /// @param day Days since the Unix epoch (UTC).
    function commitRoot(bytes32 scopeId, uint32 day, bytes32 root, string calldata datasetUri) external {
        if (msg.sender != publisher[scopeId]) revert NotPublisher();
        if (root == bytes32(0)) revert EmptyRoot();
        if (_commitments[scopeId][day].root != bytes32(0)) revert DayAlreadyCommitted();
        _commitments[scopeId][day] = Commitment({root: root, datasetUri: datasetUri, committedAt: uint64(block.timestamp)});
        emit RootCommitted(scopeId, day, root, datasetUri);
    }

    function getCommitment(bytes32 scopeId, uint32 day) external view returns (Commitment memory) {
        return _commitments[scopeId][day];
    }

    /// @notice Verify that a leaf belongs to a committed day, using sorted-pair keccak256 proofs
    ///         (the same scheme as OpenZeppelin's MerkleProof and tools/vpr/merkle.py).
    function verifyLeaf(bytes32 scopeId, uint32 day, bytes32 leaf, bytes32[] calldata proof) external view returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            computed = computed < p ? keccak256(abi.encodePacked(computed, p)) : keccak256(abi.encodePacked(p, computed));
        }
        bytes32 root = _commitments[scopeId][day].root;
        return root != bytes32(0) && computed == root;
    }
}
