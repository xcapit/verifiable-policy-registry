// SPDX-License-Identifier: Apache-2.0
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

interface IIssuerRoles {
    function issuerRole(bytes32 scopeId, address issuer) external view returns (uint8);
}

/// @title Issuer role resolver for VPR attestation schemas
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
contract IssuerRoleResolver {
    enum SchemaKind {
        Deployment, // string schoolId, bytes32 scopeId, uint256, bytes32, uint64
        IndependentTest, // string schoolId, bytes32 scopeId, uint256, bool x4, bytes32, uint64, uint64
        Conformance // bytes32 scopeId, string framework, string frameworkVersion, bytes32, uint64, uint64
    }

    address public immutable eas;
    IIssuerRoles public immutable registry;
    SchemaKind public immutable kind;
    /// @notice Role required in the registry (1 Operator, 2 Reviewer, 3 Auditor), fixed by the schema kind.
    uint8 public immutable requiredRole;
    /// @notice Number of 32-byte words in the ABI head of the schema's encoding.
    uint256 public immutable headWords;
    /// @notice Head slot holding the bytes32 scope id.
    uint256 public immutable scopeSlot;
    /// @notice Head slot holding the offset of the first string.
    uint256 public immutable offsetSlot;

    error NotEAS();
    error ZeroAddress();
    error MalformedAttestation();
    error NotPayable();
    error LengthMismatch();

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

    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    function isPayable() external pure returns (bool) {
        return false;
    }

    function _word(bytes calldata data, uint256 slot) private pure returns (bytes32) {
        return bytes32(data[slot * 32:slot * 32 + 32]);
    }

    /// @notice The scope id carried by an attestation's data, after checking the head of the encoding.
    function scopeOf(bytes calldata data) public view returns (bytes32) {
        uint256 head = headWords * 32;
        if (data.length < head) revert MalformedAttestation();
        if (uint256(_word(data, offsetSlot)) != head) revert MalformedAttestation();
        return _word(data, scopeSlot);
    }

    function _check(Attestation calldata a) private view returns (bool) {
        return registry.issuerRole(scopeOf(a.data), a.attester) == requiredRole;
    }

    function attest(Attestation calldata a) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        return _check(a);
    }

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
    function revoke(Attestation calldata) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        return true;
    }

    function multiRevoke(Attestation[] calldata list, uint256[] calldata values) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert NotPayable();
        if (values.length != list.length) revert LengthMismatch();
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] != 0) revert NotPayable();
        }
        return true;
    }
}
