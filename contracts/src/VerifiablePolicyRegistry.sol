// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @title Verifiable Policy Registry
/// @notice Public, versioned, time-limited and contestable registry of content-filtering policies.
/// @dev Each scope (for example "giga:AR:primary") is governed by a single governor address, which is
///      expected to be a Safe multisig (for example 2-of-3: UNICEF Giga, Ministry of Education and an
///      independent reviewer). The registry stores commitments only: the full policy document lives
///      off-chain at `uri` and is identified by `contentHash`. Legally restricted lists (such as the IWF
///      list) are represented only by `restrictedListHash`. No personal data is ever stored.
contract VerifiablePolicyRegistry {
    struct Scope {
        address governor;
        uint64 maxValidity; // maximum lifetime of a policy version, in seconds
        bool exists;
    }

    struct PolicyVersion {
        bytes32 contentHash; // keccak256 of the canonical policy document
        bytes32 restrictedListHash; // commitment to lists that cannot be published (0 if none)
        string uri; // where the full policy document is published (https, ipfs, ...)
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
        uint64 filedAt;
        string uri; // public description of the appeal (domain + reason), never personal data
    }

    mapping(bytes32 => Scope) public scopes;
    mapping(bytes32 => PolicyVersion[]) private _versions;
    mapping(bytes32 => Appeal) public appeals;

    event ScopeCreated(bytes32 indexed scopeId, address indexed governor, uint64 maxValidity);
    event GovernorChanged(bytes32 indexed scopeId, address indexed previousGovernor, address indexed newGovernor);
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
    event AppealFiled(bytes32 indexed appealId, bytes32 indexed scopeId, string uri);
    event AppealResolved(bytes32 indexed appealId, bool accepted);

    error ScopeAlreadyExists();
    error UnknownScope();
    error NotGovernor();
    error InvalidValidity();
    error ZeroAddress();
    error EmptyContentHash();
    error AppealAlreadyExists();
    error AppealNotOpen();
    error AppealScopeMismatch();

    modifier onlyGovernor(bytes32 scopeId) {
        Scope storage s = scopes[scopeId];
        if (!s.exists) revert UnknownScope();
        if (msg.sender != s.governor) revert NotGovernor();
        _;
    }

    /// @notice Create a new policy scope. Anyone can create a scope; trust comes from who the governor is.
    function createScope(bytes32 scopeId, address governor, uint64 maxValidity) external {
        if (scopes[scopeId].exists) revert ScopeAlreadyExists();
        if (governor == address(0)) revert ZeroAddress();
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
            emit AppealResolved(resolvesAppeal, true);
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

    /// @notice File an appeal against a block (for example an educational site that was wrongly blocked).
    /// @dev Open to anyone. The appeal id is derived from its content so duplicates are rejected.
    function fileAppeal(bytes32 scopeId, string calldata uri) external returns (bytes32 appealId) {
        if (!scopes[scopeId].exists) revert UnknownScope();
        appealId = keccak256(abi.encode(scopeId, uri));
        if (appeals[appealId].status != AppealStatus.None) revert AppealAlreadyExists();
        appeals[appealId] = Appeal({scopeId: scopeId, status: AppealStatus.Open, filedAt: uint64(block.timestamp), uri: uri});
        emit AppealFiled(appealId, scopeId, uri);
    }

    /// @notice Reject an appeal. Accepting one is done by publishing a policy version that resolves it.
    function rejectAppeal(bytes32 appealId) external {
        Appeal storage a = appeals[appealId];
        if (a.status != AppealStatus.Open) revert AppealNotOpen();
        Scope storage s = scopes[a.scopeId];
        if (msg.sender != s.governor) revert NotGovernor();
        a.status = AppealStatus.Rejected;
        emit AppealResolved(appealId, false);
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
