// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

/// @dev Attestation layout used by the Ethereum Attestation Service (EAS v1.x) when it calls a schema resolver.
///      Reproduced here so the resolver has no build-time dependency on the EAS packages; the field order must
///      match EAS `Common.sol`. Do not import EAS's `Common.sol` into the same compilation unit.
struct Attestation {
    bytes32 uid;
    bytes32 schema;
    uint64 time;
    uint64 expirationTime;
    uint64 revocationTime;
    bytes32 refUID;
    address recipient;
    address attester;
    bool revocable;
    bytes data;
}

/// @notice The part of the policy registry the resolver reads: the issuer role of an address in a scope.
interface IIssuerRoles {
    /// @param scopeId Scope identifier.
    /// @param issuer Address whose role is read.
    /// @return The role as uint8 (0 None, 1 Operator, 2 Reviewer, 3 Auditor).
    function issuerRole(bytes32 scopeId, address issuer) external view returns (uint8);
}

// slither-disable-start locked-ether
// The attest/revoke entry points must be payable to match the EAS resolver interface, but each of them reverts
// with NotPayable when called with value, and isPayable() returns false, so EAS never forwards value.
/// @title Issuer role resolver for VPR attestation schemas
/// @author Xcapit (dpg@xcapit.com)
/// @notice EAS schema resolver that accepts an attestation only if its attester holds, at issuance time, the role
///         this schema requires in the scope named inside the attestation. One resolver is deployed per schema,
///         and the schema kind fixes both the role and the encoding:
///         Deployment → Operator, IndependentTest → Reviewer, Conformance → Auditor.
/// @dev Implements the resolver interface EAS calls (attest, multiAttest, revoke, multiRevoke, isPayable) and
///      ISemver's `version()`. The scope id is a static head field, so it is read at a fixed offset; the head of
///      `data` must be complete and the offset of the schema's first string must be canonical (it points just
///      past the head), which rules out non-standard encodings of the head. The tail is not decoded: verifiers
///      decode `data` strictly and treat a decoding failure as "no attestation".
///      The role is checked at issuance only. Revocation is left to EAS (only the attester may revoke), so an
///      attestation issued while the attester held the role stays valid after the role is withdrawn; verifiers
///      compare the attestation time with the `IssuerSet` history and with `validUntil`.
///      Tested against the published EAS 1.9.0 contracts (test/EasIntegration.test.js) and fuzzed
///      (test-foundry/PropertyFuzz.t.sol). Holds no funds, keeps no state of its own, is not upgradeable.
contract IssuerRoleResolver {
    enum SchemaKind {
        Deployment, // string schoolId, bytes32 scopeId, uint256, bytes32, uint64
        IndependentTest, // string schoolId, bytes32 scopeId, uint256, bool x4, bytes32, uint64, uint64
        Conformance // bytes32 scopeId, string framework, string frameworkVersion, bytes32, uint64, uint64
    }

    /// @notice The EAS contract allowed to call this resolver.
    address public immutable eas;
    /// @notice The policy registry that records issuer roles.
    IIssuerRoles public immutable registry;
    /// @notice The schema this resolver is bound to.
    SchemaKind public immutable kind;
    /// @notice Role required in the registry (1 Operator, 2 Reviewer, 3 Auditor), fixed by the schema kind.
    uint8 public immutable requiredRole;
    /// @notice Number of 32-byte words in the ABI head of the schema's encoding.
    uint256 public immutable headWords;
    /// @notice Head slot holding the bytes32 scope id.
    uint256 public immutable scopeSlot;
    /// @notice Head slot holding the offset of the first string.
    uint256 public immutable offsetSlot;

    /// @notice The caller is not the configured EAS contract.
    error NotEAS();
    /// @notice The EAS or registry address is zero.
    error ZeroAddress();
    /// @notice The attestation data is shorter than the schema's ABI head, or its first string offset is not canonical.
    error MalformedAttestation();
    /// @notice The resolver does not accept value.
    error NotPayable();
    /// @notice A batch has a different number of attestations and values.
    error LengthMismatch();

    /// @param easAddress The EAS contract allowed to call this resolver (on OP Stack, the predeploy at 0x4200…0021).
    /// @param roles The VerifiablePolicyRegistry.
    /// @param schemaKind The schema this resolver is registered with; it fixes the role and the ABI layout.
    constructor(address easAddress, IIssuerRoles roles, SchemaKind schemaKind) {
        if (easAddress == address(0) || address(roles) == address(0)) revert ZeroAddress();
        eas = easAddress;
        registry = roles;
        kind = schemaKind;
        (uint8 role, uint256 words, uint256 sSlot, uint256 oSlot) = _layout(schemaKind);
        requiredRole = role;
        headWords = words;
        scopeSlot = sSlot;
        offsetSlot = oSlot;
    }

    /// @dev Role and ABI head layout of each schema in schemas/eas-schemas.json.
    function _layout(SchemaKind k) private pure returns (uint8, uint256, uint256, uint256) {
        if (k == SchemaKind.Deployment) return (1, 5, 1, 0);
        if (k == SchemaKind.IndependentTest) return (2, 10, 1, 0);
        return (3, 6, 0, 1);
    }

    modifier onlyEAS() {
        if (msg.sender != eas) revert NotEAS();
        _;
    }

    /// @notice Semantic version of this resolver (ISemver).
    /// @return The version string.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice EAS resolver interface: this resolver never accepts value.
    /// @return Always false.
    function isPayable() external pure returns (bool) {
        return false;
    }

    function _word(bytes calldata data, uint256 slot) private pure returns (bytes32) {
        return bytes32(data[slot * 32:slot * 32 + 32]);
    }

    /// @notice The scope id carried by an attestation's data, after checking the head of the encoding.
    /// @param data ABI-encoded attestation data of this resolver's schema.
    /// @return The scope id read from the schema's head slot.
    function scopeOf(bytes calldata data) public view returns (bytes32) {
        uint256 head = headWords * 32;
        if (data.length < head) revert MalformedAttestation();
        if (uint256(_word(data, offsetSlot)) != head) revert MalformedAttestation();
        return _word(data, scopeSlot);
    }

    // slither-disable-next-line calls-loop
    function _check(Attestation calldata a) private view returns (bool) {
        return registry.issuerRole(scopeOf(a.data), a.attester) == requiredRole;
    }

    /// @notice Called by EAS on issuance: accept only if the attester holds the schema's role in the scope.
    /// @param a The attestation being issued.
    /// @return True to accept; false makes EAS revert with InvalidAttestation.
    function attest(Attestation calldata a) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        return _check(a);
    }

    /// @notice Called by EAS on batch issuance: accept only if every attestation passes `attest`'s check.
    /// @dev Calls the trusted registry once per attestation (view calls); the batch size is bounded by EAS callers.
    /// @param list The attestations being issued.
    /// @param values Value attached to each attestation; all must be 0.
    /// @return True to accept the whole batch; false makes EAS revert with InvalidAttestations.
    function multiAttest(Attestation[] calldata list, uint256[] calldata values) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        if (values.length != list.length) revert LengthMismatch();
        for (uint256 i = 0; i < list.length; i++) {
            if (values[i] != 0) revert NotPayable();
            if (!_check(list[i])) return false;
        }
        return true;
    }

    /// @notice Revocation is left to EAS (only the original attester may revoke); the resolver does not block it.
    /// @return Always true.
    function revoke(Attestation calldata) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        return true;
    }

    /// @notice Batch revocation; the resolver does not block it.
    /// @param list The attestations being revoked.
    /// @param values Value attached to each revocation; all must be 0.
    /// @return Always true.
    function multiRevoke(Attestation[] calldata list, uint256[] calldata values) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        if (values.length != list.length) revert LengthMismatch();
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] != 0) revert NotPayable();
        }
        return true;
    }
}
// slither-disable-end locked-ether
