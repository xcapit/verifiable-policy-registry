// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

/// @title Verifiable Policy Registry
/// @author Xcapit (dpg@xcapit.com)
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
///      Invariants (checked by the Foundry invariant suite in test-foundry/RegistryInvariants.t.sol): versions are
///      append-only; every version expires within the scope's maximum validity (at most 365 days); reason codes are
///      in 1..6 and code 3 is used exactly for versions that resolve an appeal; an appeal is accepted only by a
///      version of its scope that names it, and final appeal states never change; the governor and the pending
///      governor never hold an issuer role; only the governor (or, to accept, the pending governor) mutates state.
///      Time: `currentPolicy` compares expiry with block.timestamp. On OP Stack the L2 timestamp follows the block
///      number (previous timestamp plus block time) and stays within 1800 s of its L1 origin, so expiry follows
///      wall-clock time; the sequencer can delay transactions, not move time.
///      The contract holds no funds, is not upgradeable and makes no external calls.
contract VerifiablePolicyRegistry {
    /// @notice Upper bound on any scope's maximum validity, so that "every version expires" cannot be
    ///         emptied of meaning by an arbitrarily large value.
    uint64 public constant MAX_VALIDITY_CAP = 365 days;
    /// @notice Upper bound on the length of a policy URI written on-chain.
    uint256 public constant MAX_URI_LENGTH = 256;
    /// @notice Upper bound on the length of a scope name.
    uint256 public constant MAX_NAME_LENGTH = 128;
    /// @notice Reason code of a version that accepts an appeal (docs/GOVERNANCE.md).
    uint16 public constant REASON_APPEAL_ACCEPTED = 3;
    /// @notice Highest valid reason code; valid codes are 1..MAX_REASON_CODE.
    uint16 public constant MAX_REASON_CODE = 6;

    /// @notice A governed scope (for example a country's primary-school profile).
    struct Scope {
        address governor;
        uint64 maxValidity; // maximum lifetime of a policy version, in seconds
        bool exists;
    }

    /// @notice One published policy version; versions are numbered from 1 and never modified.
    struct PolicyVersion {
        bytes32 contentHash; // keccak256 of the canonical policy document
        bytes32 restrictedListHash; // commitment to lists that cannot be published (0 if none)
        string uri; // where the full policy document is published (https, ipfs, ...); set by the governor only
        uint16 reasonCode; // why this version was published (see docs/GOVERNANCE.md)
        uint64 publishedAt; // block timestamp of publication
        uint64 expiresAt; // publishedAt + validity; the version is in force while block.timestamp < expiresAt
        bytes32 resolvesAppeal; // appeal id this version resolves (0 if none)
    }

    /// @notice Appeal state machine: None -> Open -> Accepted | Rejected; a rejected document may be filed again
    ///         in a new round, which is a new appeal.
    enum AppealStatus {
        None,
        Open,
        Accepted,
        Rejected
    }

    /// @notice One filing round of an appeal document.
    struct Appeal {
        bytes32 scopeId; // scope the appeal was filed against
        AppealStatus status;
        uint32 round; // 1 for the first filing of a document, incremented on resubmission after rejection
        uint64 filedAt; // block timestamp of the filing
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

    /// @notice Scope state by scope id.
    mapping(bytes32 => Scope) public scopes;
    /// @notice Name a scope was created with (informative; verifiers pin the scope id).
    mapping(bytes32 => string) public scopeName;
    /// @notice Address proposed as the next governor of a scope, or zero.
    mapping(bytes32 => address) public pendingGovernor;
    mapping(bytes32 => PolicyVersion[]) private _versions;
    /// @notice Appeals by appeal id (see appealIdOf).
    mapping(bytes32 => Appeal) public appeals;
    /// @notice Latest filing round per (scope, appeal document).
    mapping(bytes32 => uint32) public appealRounds;
    /// @notice Attestation issuer role of an address within a scope.
    mapping(bytes32 => mapping(address => Role)) public issuerRole;

    /// @notice A scope was created; `governor` is its creator and first governor.
    event ScopeCreated(bytes32 indexed scopeId, address indexed governor, string name, uint64 maxValidity);
    /// @notice A handover was proposed; a zero `proposedGovernor` cancels a pending proposal.
    event GovernorProposed(bytes32 indexed scopeId, address indexed currentGovernor, address indexed proposedGovernor);
    /// @notice The proposed governor accepted and now governs the scope.
    event GovernorChanged(bytes32 indexed scopeId, address indexed previousGovernor, address indexed newGovernor);
    /// @notice An attestation role was granted, changed or revoked (Role.None).
    event IssuerSet(bytes32 indexed scopeId, address indexed issuer, Role role);
    /// @notice A new policy version was appended.
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
    /// @notice An appeal document hash was filed (round 1, or a later round after a rejection).
    event AppealFiled(bytes32 indexed appealId, bytes32 indexed scopeId, bytes32 documentHash, uint32 round);
    /// @notice An appeal was accepted (resolution = content hash of the accepting version) or rejected
    ///         (resolution = hash of the published reasoned decision).
    event AppealResolved(bytes32 indexed appealId, bool accepted, bytes32 resolutionHash);

    /// @notice The caller already created a scope with this name.
    error ScopeAlreadyExists();
    /// @notice The scope does not exist.
    error UnknownScope();
    /// @notice The caller is not the scope's governor.
    error NotGovernor();
    /// @notice The caller is not the pending governor, or no handover is pending.
    error NotPendingGovernor();
    /// @notice A validity is 0, above the scope's maxValidity, or a maxValidity above MAX_VALIDITY_CAP.
    error InvalidValidity();
    /// @notice An issuer address is zero.
    error ZeroAddress();
    /// @notice A scope name is empty.
    error EmptyName();
    /// @notice A scope name is longer than MAX_NAME_LENGTH bytes.
    error NameTooLong();
    /// @notice A version number is 0 or above the number of versions.
    error UnknownVersion();
    /// @notice A policy content hash is 0.
    error EmptyContentHash();
    /// @notice An appeal document hash is 0.
    error EmptyDocumentHash();
    /// @notice A rejection must carry the hash of a published reasoned decision.
    error EmptyReason();
    /// @notice A policy URI is longer than MAX_URI_LENGTH bytes.
    error UriTooLong();
    /// @notice A reason code is outside 1..MAX_REASON_CODE, or code 3 and the resolved appeal do not match.
    error InvalidReasonCode();
    /// @notice The governor, the pending governor or a proposed governor would hold an issuer role.
    error GovernorCannotHoldRole();
    /// @notice The document already has an open or accepted appeal.
    error AppealAlreadyExists();
    /// @notice The appeal is not open.
    error AppealNotOpen();
    /// @notice The appeal belongs to another scope.
    error AppealScopeMismatch();

    modifier onlyGovernor(bytes32 scopeId) {
        Scope storage s = scopes[scopeId];
        if (!s.exists) revert UnknownScope();
        if (msg.sender != s.governor) revert NotGovernor();
        _;
    }

    /// @notice Scope id for a scope name created by a given governor: keccak256(abi.encode(governor, name)).
    /// @param governor The creating governor.
    /// @param name The scope name.
    /// @return The scope id.
    function scopeIdOf(address governor, string memory name) public pure returns (bytes32) {
        return keccak256(abi.encode(governor, name));
    }

    /// @notice Create a scope governed by the caller. The id is derived from the caller and the name, so another
    ///         address cannot occupy the same id first.
    /// @param name Scope name, 1 to MAX_NAME_LENGTH bytes (convention: <programme>:<ISO 3166-1 alpha-2>:<profile>).
    /// @param maxValidity Maximum lifetime of a policy version, in seconds; 0 < maxValidity <= MAX_VALIDITY_CAP.
    /// @return scopeId The new scope id, scopeIdOf(msg.sender, name).
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
    /// @param scopeId Scope identifier.
    /// @param newGovernor Proposed governor, or address(0) to cancel.
    function proposeGovernor(bytes32 scopeId, address newGovernor) external onlyGovernor(scopeId) {
        if (issuerRole[scopeId][newGovernor] != Role.None) revert GovernorCannotHoldRole();
        pendingGovernor[scopeId] = newGovernor;
        emit GovernorProposed(scopeId, msg.sender, newGovernor);
    }

    /// @notice Second step: the proposed governor accepts, which proves it can act before it takes over.
    /// @param scopeId Scope identifier.
    function acceptGovernor(bytes32 scopeId) external {
        if (!scopes[scopeId].exists) revert UnknownScope();
        address pending = pendingGovernor[scopeId];
        if (pending == address(0) || msg.sender != pending) revert NotPendingGovernor();
        // Defence in depth: unreachable while proposeGovernor and setIssuer enforce the same rule.
        if (issuerRole[scopeId][pending] != Role.None) revert GovernorCannotHoldRole();
        address previous = scopes[scopeId].governor;
        scopes[scopeId].governor = pending;
        delete pendingGovernor[scopeId];
        emit GovernorChanged(scopeId, previous, pending);
    }

    /// @notice Grant, change or revoke (Role.None) the attestation role of an address in a scope. Neither the
    ///         governor nor the pending governor can be given a role.
    /// @param scopeId Scope identifier.
    /// @param issuer Address whose role changes.
    /// @param role New role.
    function setIssuer(bytes32 scopeId, address issuer, Role role) external onlyGovernor(scopeId) {
        if (issuer == address(0)) revert ZeroAddress();
        if (issuer == msg.sender || (role != Role.None && issuer == pendingGovernor[scopeId])) {
            revert GovernorCannotHoldRole();
        }
        issuerRole[scopeId][issuer] = role;
        emit IssuerSet(scopeId, issuer, role);
    }

    /// @notice Publish a new policy version. It becomes the policy in force until it expires or is replaced. If
    ///         `resolvesAppeal` is set, the appeal is accepted in the same transaction.
    /// @param scopeId Scope identifier.
    /// @param contentHash keccak256 of the canonical policy document (docs/INTERFACES.md I1); must not be 0.
    /// @param restrictedListHash Commitment to lists that cannot be published, or 0 if none.
    /// @param uri Where the policy document is published; at most MAX_URI_LENGTH bytes.
    /// @param reasonCode One of the codes in docs/GOVERNANCE.md (1..6); 3 (appeal accepted) if and only if
    ///        `resolvesAppeal` is set.
    /// @param validity Lifetime in seconds; must not exceed the scope's maxValidity.
    /// @param resolvesAppeal Id of an open appeal of this scope that this version accepts, or 0.
    /// @return version The new version number (1-based).
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

    /// @notice Id of the appeal for a document in a given filing round: keccak256(abi.encode(scopeId, documentHash, round)).
    /// @param scopeId Scope identifier.
    /// @param documentHash keccak256 of the canonical appeal document.
    /// @param round Filing round, from 1.
    /// @return The appeal id.
    function appealIdOf(bytes32 scopeId, bytes32 documentHash, uint32 round) public pure returns (bytes32) {
        return keccak256(abi.encode(scopeId, documentHash, round));
    }

    /// @notice File an appeal against a block. Open to anyone; only the hash of the appeal document is stored.
    ///         Appeal documents carry a random nonce (format vpr-appeal/3), so a document cannot be guessed and
    ///         pre-filed by someone else. A document can be filed again after a rejection (new round); rounds
    ///         are not an escalation count. Anyone, including a third party, can re-file a rejected document or
    ///         file the same document first (the appeal exists either way); the filer is not recorded, so as not
    ///         to link appellants to appeals. Spam is limited off-chain by the relayer (VPR-017).
    /// @param scopeId Scope identifier.
    /// @param documentHash keccak256 of the canonical appeal document (format vpr-appeal/3); must not be 0.
    /// @return appealId The id of the new appeal.
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
    /// @param appealId Id of an open appeal.
    /// @param reasonHash Hash of the published reasoned decision; must not be 0.
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
    /// @param scopeId Scope identifier.
    /// @return The number of versions.
    function versionCount(bytes32 scopeId) external view returns (uint256) {
        return _versions[scopeId].length;
    }

    /// @notice Read a specific version (1-based).
    /// @param scopeId Scope identifier.
    /// @param version Version number, from 1 to versionCount(scopeId).
    /// @return The version.
    function getVersion(bytes32 scopeId, uint256 version) external view returns (PolicyVersion memory) {
        if (version == 0 || version > _versions[scopeId].length) revert UnknownVersion();
        return _versions[scopeId][version - 1];
    }

    /// @notice The latest version and whether it is still in force.
    /// @dev Compares expiry with block.timestamp on purpose; see the contract-level note on time.
    /// @param scopeId Scope identifier.
    /// @return version The latest version number, or 0 if none.
    /// @return policy The latest version (zero values if none).
    /// @return inForce Whether the latest version has not expired.
    // slither-disable-next-line timestamp
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
