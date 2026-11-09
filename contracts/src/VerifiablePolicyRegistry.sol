// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

/// @title Verifiable Policy Registry
/// @notice Public, versioned, time-limited and contestable registry of content-filtering policies.
/// @dev Each scope is governed by a single governor address, which is expected to be a multisig contract
///      (for example a Safe with an m-of-n threshold); the registry itself only checks the address. The
///      registry stores commitments only: the full policy document lives off-chain at `uri` and is identified
///      by `contentHash`. Legally restricted lists are represented only by `restrictedListHash`. Appeals are
///      recorded as hashes of appeal documents validated off-chain.
///      Scope ids are derived on-chain from the creating governor and a scope name
///      (`scopeIdOf(governor, name)`), so a canonical name cannot be front-run by another address. Verifiers
///      still pin the chain id, this contract's address and the expected governor from a deployment manifest.
///      The id binds the creating governor: after a handover it no longer equals scopeIdOf(currentGovernor, name),
///      and the new governor could create a second scope with the same name under a different id. Verifiers
///      therefore pin the scope id itself, never recompute it from the current governor.
///      Separation of roles is enforced per address: the governor never holds an issuer role, including after a
///      handover. One institution controlling several addresses is a governance matter, not a contract check.
contract VerifiablePolicyRegistry {
    /// @notice Upper bound on any scope's maximum validity, so that "every version expires" cannot be
    ///         emptied of meaning by an arbitrarily large value.
    uint64 public constant MAX_VALIDITY_CAP = 365 days;
    /// @notice Upper bound on the length of a policy URI written on-chain.
    uint256 public constant MAX_URI_LENGTH = 256;
    /// @notice Upper bound on the length of a scope name.
    uint256 public constant MAX_NAME_LENGTH = 128;
    uint16 public constant REASON_APPEAL_ACCEPTED = 3;
    uint16 public constant MAX_REASON_CODE = 6;

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
        bytes32 documentHash; // keccak256 of the appeal document, validated off-chain
        bytes32 resolutionHash; // hash of the reasoned rejection, or the content hash of the accepting version
    }

    /// @notice Roles that may issue attestations for a scope. One address holds at most one role per scope,
    ///         and the governor cannot hold a role itself.
    enum Role {
        None,
        Operator,
        Reviewer,
        Auditor
    }

    mapping(bytes32 => Scope) public scopes;
    mapping(bytes32 => string) public scopeName;
    mapping(bytes32 => address) public pendingGovernor;
    mapping(bytes32 => PolicyVersion[]) private _versions;
    mapping(bytes32 => Appeal) public appeals;
    /// @notice Latest filing round per (scope, appeal document).
    mapping(bytes32 => uint32) public appealRounds;
    /// @notice Attestation issuer role of an address within a scope.
    mapping(bytes32 => mapping(address => Role)) public issuerRole;

    event ScopeCreated(bytes32 indexed scopeId, address indexed governor, string name, uint64 maxValidity);
    event GovernorProposed(bytes32 indexed scopeId, address indexed currentGovernor, address indexed proposedGovernor);
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
    error NotPendingGovernor();
    error InvalidValidity();
    error ZeroAddress();
    error EmptyName();
    error NameTooLong();
    error UnknownVersion();
    error EmptyContentHash();
    error EmptyDocumentHash();
    error EmptyReason();
    error UriTooLong();
    error InvalidReasonCode();
    error GovernorCannotHoldRole();
    error AppealAlreadyExists();
    error AppealNotOpen();
    error AppealScopeMismatch();

    modifier onlyGovernor(bytes32 scopeId) {
        Scope storage s = scopes[scopeId];
        if (!s.exists) revert UnknownScope();
        if (msg.sender != s.governor) revert NotGovernor();
        _;
    }

    /// @notice Scope id for a scope name created by a given governor: keccak256(abi.encode(governor, name)).
    function scopeIdOf(address governor, string memory name) public pure returns (bytes32) {
        return keccak256(abi.encode(governor, name));
    }

    /// @notice Create a scope governed by the caller. The id is derived from the caller and the name, so another
    ///         address cannot occupy the same id first.
    function createScope(string calldata name, uint64 maxValidity) external returns (bytes32 scopeId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(name).length > MAX_NAME_LENGTH) revert NameTooLong();
        if (maxValidity == 0 || maxValidity > MAX_VALIDITY_CAP) revert InvalidValidity();
        scopeId = scopeIdOf(msg.sender, name);
        if (scopes[scopeId].exists) revert ScopeAlreadyExists();
        scopes[scopeId] = Scope({governor: msg.sender, maxValidity: maxValidity, exists: true});
        scopeName[scopeId] = name;
        emit ScopeCreated(scopeId, msg.sender, name, maxValidity);
    }

    /// @notice First step of a governor handover. Proposing address(0) cancels a pending proposal. An address that
    ///         holds an issuer role in the scope cannot be proposed; its role must be revoked first.
    function proposeGovernor(bytes32 scopeId, address newGovernor) external onlyGovernor(scopeId) {
        if (issuerRole[scopeId][newGovernor] != Role.None) revert GovernorCannotHoldRole();
        pendingGovernor[scopeId] = newGovernor;
        emit GovernorProposed(scopeId, msg.sender, newGovernor);
    }

    /// @notice Second step: the proposed governor accepts, which proves it can act before it takes over.
    function acceptGovernor(bytes32 scopeId) external {
        if (!scopes[scopeId].exists) revert UnknownScope();
        address pending = pendingGovernor[scopeId];
        if (pending == address(0) || msg.sender != pending) revert NotPendingGovernor();
        if (issuerRole[scopeId][pending] != Role.None) revert GovernorCannotHoldRole();
        address previous = scopes[scopeId].governor;
        scopes[scopeId].governor = pending;
        delete pendingGovernor[scopeId];
        emit GovernorChanged(scopeId, previous, pending);
    }

    /// @notice Grant, change or revoke (Role.None) the attestation role of an address in a scope.
    function setIssuer(bytes32 scopeId, address issuer, Role role) external onlyGovernor(scopeId) {
        if (issuer == address(0)) revert ZeroAddress();
        if (issuer == msg.sender || (role != Role.None && issuer == pendingGovernor[scopeId])) {
            revert GovernorCannotHoldRole();
        }
        issuerRole[scopeId][issuer] = role;
        emit IssuerSet(scopeId, issuer, role);
    }

    /// @notice Publish a new policy version. It becomes the policy in force until it expires or is replaced.
    /// @param reasonCode One of the codes in docs/GOVERNANCE.md (1..6); 3 (appeal accepted) if and only if
    ///        `resolvesAppeal` is set.
    /// @param validity Lifetime in seconds; must not exceed the scope's maxValidity.
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
        if (bytes(uri).length > MAX_URI_LENGTH) revert UriTooLong();
        if (reasonCode == 0 || reasonCode > MAX_REASON_CODE) revert InvalidReasonCode();
        if ((reasonCode == REASON_APPEAL_ACCEPTED) != (resolvesAppeal != bytes32(0))) revert InvalidReasonCode();

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

    /// @notice File an appeal against a block. Open to anyone; only the hash of the appeal document is stored.
    ///         Appeal documents carry a random nonce (format vpr-appeal/3), so a document cannot be guessed and
    ///         pre-filed by someone else. A document can be filed again after a rejection (new round); rounds
    ///         are not an escalation count. Anyone, including a third party, can re-file a rejected document or
    ///         file the same document first (the appeal exists either way); the filer is not recorded, so as not
    ///         to link appellants to appeals. Spam is limited off-chain by the relayer (VPR-017).
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
        if (version == 0 || version > _versions[scopeId].length) revert UnknownVersion();
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
