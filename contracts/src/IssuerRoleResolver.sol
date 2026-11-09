// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @dev Attestation layout used by the Ethereum Attestation Service (EAS) when it calls a schema resolver.
///      Reproduced here so the resolver has no build-time dependency on the EAS packages.
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
///         this schema requires in the scope named inside the attestation. One resolver is deployed per schema:
///         Deployment → Operator, IndependentTest → Reviewer, Conformance → Auditor.
/// @dev Implements the resolver interface EAS calls (attest, multiAttest, revoke, multiRevoke, isPayable).
///      `scopeSlot` is the ABI head slot that holds the bytes32 scope id in the schema's encoding:
///      1 for VPR.Deployment.v1 and VPR.IndependentTest.v1 (after the dynamic schoolId), 0 for VPR.Conformance.v1.
contract IssuerRoleResolver {
    address public immutable eas;
    IIssuerRoles public immutable registry;
    uint8 public immutable requiredRole;
    uint8 public immutable scopeSlot;

    error NotEAS();
    error ZeroAddress();
    error InvalidConfiguration();
    error MalformedAttestation();
    error InsufficientValue();

    constructor(address easAddress, IIssuerRoles roles, uint8 role, uint8 slot) {
        if (easAddress == address(0) || address(roles) == address(0)) revert ZeroAddress();
        if (role == 0 || role > 3 || slot > 1) revert InvalidConfiguration();
        eas = easAddress;
        registry = roles;
        requiredRole = role;
        scopeSlot = slot;
    }

    modifier onlyEAS() {
        if (msg.sender != eas) revert NotEAS();
        _;
    }

    function isPayable() external pure returns (bool) {
        return false;
    }

    /// @notice The scope id carried by an attestation's data, read from the schema's head slot.
    function scopeOf(bytes calldata data) public view returns (bytes32) {
        uint256 start = uint256(scopeSlot) * 32;
        if (data.length < start + 32) revert MalformedAttestation();
        return bytes32(data[start:start + 32]);
    }

    function _check(Attestation calldata a) private view returns (bool) {
        return registry.issuerRole(scopeOf(a.data), a.attester) == requiredRole;
    }

    function attest(Attestation calldata a) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert InsufficientValue();
        return _check(a);
    }

    function multiAttest(Attestation[] calldata list, uint256[] calldata values) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert InsufficientValue();
        for (uint256 i = 0; i < list.length; i++) {
            if (values.length > i && values[i] != 0) revert InsufficientValue();
            if (!_check(list[i])) return false;
        }
        return true;
    }

    /// @notice Revocation is left to EAS (only the original attester may revoke); the resolver does not block it.
    function revoke(Attestation calldata) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert InsufficientValue();
        return true;
    }

    function multiRevoke(Attestation[] calldata, uint256[] calldata) external payable onlyEAS returns (bool) {
        if (msg.value != 0) revert InsufficientValue();
        return true;
    }
}
