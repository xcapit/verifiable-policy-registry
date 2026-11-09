// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @title Verifiable Policy Registry
/// @notice Public, versioned, time-limited and contestable registry of content-filtering policies.
/// @dev Each scope (for example "giga:AR:primary") is governed by a single governor address, which is
///      expected to be a Safe multisig (for example 2-of-3: UNICEF Giga, Ministry of Education and an
///      independent reviewer). The registry stores commitments only: the full policy document lives
///      off-chain at `uri` and is identified by `contentHash`. Legally restricted lists (such as the IWF
///      list) are represented only by `restrictedListHash`. Appeals are recorded as hashes of appeal
///      documents validated off-chain, so no caller can place free text on-chain through an appeal.
///      Scope names are not authenticated by the contract: verifiers must pin the chain id, this contract's
///      address, the scope id and the expected governor from a deployment manifest published by the partners.
contract VerifiablePolicyRegistry {
    struct Scope {
        address governor;
        uint64 maxValidity; // maximum lifetime of a policy version, in seconds
        bool exists;
    }

    struct PolicyVersion {
        bytes32 contentHash; // keccak256 of the canonical policy document
        bytes32 restrictedListHash; // commitment to lists that cannot be published (0 if none)
        string uri; // where the full policy document is published (https, ipfs, ...); set by the governor only
        uint16 reasonCode; // why this version was published (see docs/GOVERNANCE.md)
        uint64 publishedAt;
        uint64 expiresAt;
        bytes32 resolvesAppeal; // appeal id this version resolves (0 if none)
    }

    enum AppealStatus {
        None,
        Open,
        Accepted,
        Rejected
    }

    struct Appeal {
        bytes32 scopeId;
        AppealStatus status;
        uint32 round; // 1 for the first filing of a document, incremented on resubmission after rejection
        uint64 filedAt;
        bytes32 documentHash; // keccak256 of the appeal document (format vpr-appeal/2), validated off-chain
        bytes32 resolutionHash; // hash of the reasoned rejection, or the content hash of the accepting version
    }

    /// @notice Roles that may issue attestations for a scope. One address holds at most one role per scope,
    ///         so the operator can never also be the reviewer or the auditor.
    enum Role {
        None,
        Operator,
        Reviewer,
        Auditor
    }

    mapping(bytes32 => Scope) public scopes;
    mapping(bytes32 => PolicyVersion[]) private _versions;
    mapping(bytes32 => Appeal) public appeals;
    /// @notice Latest filing round per (scope, appeal document).
    mapping(bytes32 => uint32) public appealRounds;
    /// @notice Attestation issuer role of an address within a scope.
    mapping(bytes32 => mapping(address => Role)) public issuerRole;

    event ScopeCreated(bytes32 indexed scopeId, address indexed governor, uint64 maxValidity);
    event GovernorChanged(bytes32 indexed scopeId, address indexed previousGovernor, address indexed newGovernor);
    event IssuerSet(bytes32 indexed scopeId, address indexed issuer, Role role);
    event PolicyPublished(
        bytes32 indexed scopeId,
        uint256 indexed version,
        bytes32 contentHash,
        bytes32 restrictedListHash,
        string uri,
        uint16 reasonCode,
        uint64 expiresAt,
        bytes32 resolvesAppeal
    );
    event AppealFiled(bytes32 indexed appealId, bytes32 indexed scopeId, bytes32 documentHash, uint32 round);
    event AppealResolved(bytes32 indexed appealId, bool accepted, bytes32 resolutionHash);

    error ScopeAlreadyExists();
    error UnknownScope();
    error NotGovernor();
    error InvalidValidity();
    error ZeroAddress();
    error EmptyContentHash();
    error EmptyDocumentHash();
    error EmptyReason();
    error AppealAlreadyExists();
    error AppealNotOpen();
    error AppealScopeMismatch();

    modifier onlyGovernor(bytes32 scopeId) {
        Scope storage s = scopes[scopeId];
        if (!s.exists) revert UnknownScope();
        if (msg.sender != s.governor) revert NotGovernor();
        _;
    }

    /// @notice Create a new policy scope. Only the governor itself can create its scope, so nobody can create a
    ///         scope that appears to be governed by someone else's Safe.
    function createScope(bytes32 scopeId, address governor, uint64 maxValidity) external {
        if (scopes[scopeId].exists) revert ScopeAlreadyExists();
        if (governor == address(0)) revert ZeroAddress();
        if (msg.sender != governor) revert NotGovernor();
        if (maxValidity == 0) revert InvalidValidity();
        scopes[scopeId] = Scope({governor: governor, maxValidity: maxValidity, exists: true});
        emit ScopeCreated(scopeId, governor, maxValidity);
    }

    /// @notice Hand the scope over to a new governor (for example a rotated Safe).
    function setGovernor(bytes32 scopeId, address newGovernor) external onlyGovernor(scopeId) {
        if (newGovernor == address(0)) revert ZeroAddress();
        address previous = scopes[scopeId].governor;
        scopes[scopeId].governor = newGovernor;
        emit GovernorChanged(scopeId, previous, newGovernor);
    }

    /// @notice Grant, change or revoke (Role.None) the attestation role of an address in a scope.
    function setIssuer(bytes32 scopeId, address issuer, Role role) external onlyGovernor(scopeId) {
        if (issuer == address(0)) revert ZeroAddress();
        issuerRole[scopeId][issuer] = role;
        emit IssuerSet(scopeId, issuer, role);
    }

    /// @notice Publish a new policy version. It becomes the policy in force until it expires or is replaced.
    /// @param validity Lifetime in seconds; must not exceed the scope's maxValidity. Expiry is mandatory so
    ///        that no block becomes permanent by default.
    /// @param resolvesAppeal Appeal id this version resolves (accepted appeal), or 0.
    function publishPolicy(
        bytes32 scopeId,
        bytes32 contentHash,
        bytes32 restrictedListHash,
        string calldata uri,
        uint16 reasonCode,
        uint64 validity,
        bytes32 resolvesAppeal
    ) external onlyGovernor(scopeId) returns (uint256 version) {
        if (contentHash == bytes32(0)) revert EmptyContentHash();
        if (validity == 0 || validity > scopes[scopeId].maxValidity) revert InvalidValidity();

        if (resolvesAppeal != bytes32(0)) {
            Appeal storage a = appeals[resolvesAppeal];
            if (a.status != AppealStatus.Open) revert AppealNotOpen();
            if (a.scopeId != scopeId) revert AppealScopeMismatch();
            a.status = AppealStatus.Accepted;
            a.resolutionHash = contentHash;
            emit AppealResolved(resolvesAppeal, true, contentHash);
        }

        uint64 nowTs = uint64(block.timestamp);
        _versions[scopeId].push(
            PolicyVersion({
                contentHash: contentHash,
                restrictedListHash: restrictedListHash,
                uri: uri,
                reasonCode: reasonCode,
                publishedAt: nowTs,
                expiresAt: nowTs + validity,
                resolvesAppeal: resolvesAppeal
            })
        );
        version = _versions[scopeId].length; // versions are 1-based
        emit PolicyPublished(
            scopeId, version, contentHash, restrictedListHash, uri, reasonCode, nowTs + validity, resolvesAppeal
        );
    }

    /// @notice Id of the appeal for a document in a given filing round.
    function appealIdOf(bytes32 scopeId, bytes32 documentHash, uint32 round) public pure returns (bytes32) {
        return keccak256(abi.encode(scopeId, documentHash, round));
    }

    /// @notice File an appeal against a block (for example an educational site that was wrongly blocked).
    /// @dev Open to anyone. Only the hash of the appeal document is stored; the document itself is validated and
    ///      published off-chain by the block page relayer. A document can be filed again after a rejection, which
    ///      opens a new round; it cannot be filed while an earlier round is open or after it was accepted.
    function fileAppeal(bytes32 scopeId, bytes32 documentHash) external returns (bytes32 appealId) {
        if (!scopes[scopeId].exists) revert UnknownScope();
        if (documentHash == bytes32(0)) revert EmptyDocumentHash();
        bytes32 key = keccak256(abi.encode(scopeId, documentHash));
        uint32 round = appealRounds[key];
        if (round != 0) {
            AppealStatus previous = appeals[appealIdOf(scopeId, documentHash, round)].status;
            if (previous != AppealStatus.Rejected) revert AppealAlreadyExists();
        }
        round += 1;
        appealRounds[key] = round;
        appealId = appealIdOf(scopeId, documentHash, round);
        appeals[appealId] = Appeal({
            scopeId: scopeId,
            status: AppealStatus.Open,
            round: round,
            filedAt: uint64(block.timestamp),
            documentHash: documentHash,
            resolutionHash: bytes32(0)
        });
        emit AppealFiled(appealId, scopeId, documentHash, round);
    }

    /// @notice Reject an appeal with a reasoned decision, committed by its hash and published off-chain.
    ///         Accepting one is done by publishing a policy version that resolves it.
    function rejectAppeal(bytes32 appealId, bytes32 reasonHash) external {
        Appeal storage a = appeals[appealId];
        if (a.status != AppealStatus.Open) revert AppealNotOpen();
        if (msg.sender != scopes[a.scopeId].governor) revert NotGovernor();
        if (reasonHash == bytes32(0)) revert EmptyReason();
        a.status = AppealStatus.Rejected;
        a.resolutionHash = reasonHash;
        emit AppealResolved(appealId, false, reasonHash);
    }

    /// @notice Number of versions published for a scope.
    function versionCount(bytes32 scopeId) external view returns (uint256) {
        return _versions[scopeId].length;
    }

    /// @notice Read a specific version (1-based).
    function getVersion(bytes32 scopeId, uint256 version) external view returns (PolicyVersion memory) {
        return _versions[scopeId][version - 1];
    }

    /// @notice The latest version and whether it is still in force.
    function currentPolicy(bytes32 scopeId)
        external
        view
        returns (uint256 version, PolicyVersion memory policy, bool inForce)
    {
        uint256 n = _versions[scopeId].length;
        if (n == 0) return (0, policy, false);
        policy = _versions[scopeId][n - 1];
        return (n, policy, block.timestamp < policy.expiresAt);
    }
}
