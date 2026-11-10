// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../src/VerifiablePolicyRegistry.sol";
import {MetricsAnchor, IPolicyRegistry} from "../src/MetricsAnchor.sol";
import {IssuerRoleResolver, IIssuerRoles, Attestation} from "../src/IssuerRoleResolver.sol";

/// @title Property fuzz tests
/// @notice Stateless properties over arbitrary inputs: Merkle proofs of dataset format 2, scope identifiers, and
///         the resolver's reading of attestation data.
contract PropertyFuzz is Test {
    VerifiablePolicyRegistry reg;
    MetricsAnchor anchor;
    bytes32 scope;
    address governor = makeAddr("governor");
    address publisher = makeAddr("publisher");
    uint32 constant DAY = 20758; // 2026-11-01

    function setUp() public {
        vm.warp(20767 days);
        reg = new VerifiablePolicyRegistry();
        vm.prank(governor);
        scope = reg.createScope("giga:XX:primary", 90 days);
        anchor = new MetricsAnchor(IPolicyRegistry(address(reg)));
        uint32 noLimit = anchor.NO_LAG_LIMIT(); // read before vm.prank, which applies to the next call only
        vm.prank(governor);
        anchor.setPublisher(scope, publisher, noLimit);
    }

    // ---------------------------------------------------------------- shared cross-language test vector

    /// The leaf and root of the shared vector (tools/tests, contracts/test/MetricsAnchor.test.js) are reproduced
    /// exactly: an independent check of the leaf encoding, since the fuzz tests below build leaves with leafHash.
    function test_sharedVector() public view {
        bytes32 l0 = anchor.leafHash(DAY, "giga-0001", "adult", 40);
        bytes32 l1 = anchor.leafHash(DAY, "giga-0001", "malware", 25);
        bytes32 l2 = anchor.leafHash(DAY, "giga-0003", "malware", 25);
        assertEq(l0, 0xd16b6d8f55bf68aa54ca8d755e0c0beb5c84c2e63e9eda7ab55abc5579b8a348);
        assertEq(_node(_node(l0, l1), l2), 0x7d91cbb18fd37a7042393e2043b2fed8a1d0723bdf8845d72bc7188febdf6747);
    }

    // ---------------------------------------------------------------- Merkle tree of format 2 (reference model)

    function _node(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(bytes1(0x01), a, b)) : keccak256(abi.encodePacked(bytes1(0x01), b, a));
    }

    /// @dev Root and proof for leaf `idx`, built level by level; an odd last node is promoted unchanged.
    function _rootAndProof(bytes32[] memory level, uint256 idx) internal pure returns (bytes32, bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](32);
        uint256 len;
        while (level.length > 1) {
            uint256 sibling = idx ^ 1;
            if (sibling < level.length) proof[len++] = level[sibling];
            bytes32[] memory next = new bytes32[]((level.length + 1) / 2);
            for (uint256 i = 0; i < level.length; i += 2) {
                next[i / 2] = i + 1 < level.length ? _node(level[i], level[i + 1]) : level[i];
            }
            level = next;
            idx /= 2;
        }
        assembly {
            mstore(proof, len)
        }
        return (level[0], proof);
    }

    /// Any row of any release verifies against the anchored root; changing its count, unit, category or day
    /// makes it fail.
    function testFuzz_merkleProofs(uint8 sizeSeed, uint256 pickSeed, uint256 countSeed) public {
        uint256 n = bound(sizeSeed, 1, 40);
        uint256 pick = bound(pickSeed, 0, n - 1);
        string[] memory units = new string[](n);
        uint256[] memory counts = new uint256[](n);
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            units[i] = string(abi.encodePacked("giga-", vm.toString(i)));
            counts[i] = bound(uint256(keccak256(abi.encode(countSeed, i))), 10, 1e9);
            leaves[i] = anchor.leafHash(DAY, units[i], "malware", counts[i]);
        }
        (bytes32 root, bytes32[] memory proof) = _rootAndProof(leaves, pick);
        vm.prank(publisher);
        anchor.commitRoot(scope, DAY, root, "ipfs://d");

        assertTrue(anchor.verifyRow(scope, DAY, units[pick], "malware", counts[pick], proof));
        assertFalse(anchor.verifyRow(scope, DAY, units[pick], "malware", counts[pick] + 1, proof));
        assertFalse(anchor.verifyRow(scope, DAY, units[pick], "phishing", counts[pick], proof));
        assertFalse(anchor.verifyRow(scope, DAY, string(abi.encodePacked(units[pick], "x")), "malware", counts[pick], proof));
        assertFalse(anchor.verifyRow(scope, DAY - 1, units[pick], "malware", counts[pick], proof));
    }

    /// Length prefixes make the leaf encoding unambiguous: moving bytes between unit and category changes the leaf.
    function testFuzz_leafUnambiguous(string calldata a, string calldata b, uint256 count) public view {
        vm.assume(bytes(a).length > 0 && bytes(a).length < 200 && bytes(b).length < 200);
        bytes memory ab = bytes(a);
        // split `a` into a shorter unit and move the remainder in front of the category
        string memory unit2 = string(_slice(ab, 0, ab.length - 1));
        string memory cat2 = string(abi.encodePacked(ab[ab.length - 1], b));
        assertTrue(anchor.leafHash(DAY, a, b, count) != anchor.leafHash(DAY, unit2, cat2, count));
    }

    function _slice(bytes memory s, uint256 from, uint256 to) internal pure returns (bytes memory out) {
        out = new bytes(to - from);
        for (uint256 i = from; i < to; i++) out[i - from] = s[i];
    }

    // ---------------------------------------------------------------- scope identifiers

    /// Distinct (governor, name) pairs give distinct scope ids, so a canonical name cannot be pre-empted.
    function testFuzz_scopeIdsDistinct(address g1, string calldata n1, address g2, string calldata n2) public view {
        vm.assume(g1 != g2 || keccak256(bytes(n1)) != keccak256(bytes(n2)));
        assertTrue(reg.scopeIdOf(g1, n1) != reg.scopeIdOf(g2, n2));
    }

    /// Creating the same name from another address never touches the original scope.
    function testFuzz_noScopeSquatting(address squatter) public {
        vm.assume(squatter != governor && squatter != address(0));
        vm.prank(squatter);
        bytes32 other = reg.createScope("giga:XX:primary", 90 days);
        assertTrue(other != scope);
        (address g,,) = reg.scopes(scope);
        assertEq(g, governor);
    }

    // ---------------------------------------------------------------- resolver reading of attestation data

    /// For any well-formed encoding of each schema, the resolver reads exactly the scope id a decoder reads.
    function testFuzz_resolverReadsScope(bytes32 s, string calldata school, string calldata framework, uint256 version) public {
        vm.assume(bytes(school).length < 300 && bytes(framework).length < 300);
        IIssuerRoles roles = IIssuerRoles(address(reg));
        IssuerRoleResolver dep = new IssuerRoleResolver(address(this), roles, IssuerRoleResolver.SchemaKind.Deployment);
        IssuerRoleResolver test_ = new IssuerRoleResolver(address(this), roles, IssuerRoleResolver.SchemaKind.IndependentTest);
        IssuerRoleResolver conf = new IssuerRoleResolver(address(this), roles, IssuerRoleResolver.SchemaKind.Conformance);
        assertEq(dep.scopeOf(abi.encode(school, s, version, bytes32(0), uint64(1))), s);
        assertEq(
            test_.scopeOf(abi.encode(school, s, version, true, false, true, false, bytes32(0), uint64(1), uint64(2))), s
        );
        assertEq(conf.scopeOf(abi.encode(s, framework, school, bytes32(0), uint64(1), uint64(2))), s);
    }

    function _attestation(address attester, bytes memory data) internal pure returns (Attestation memory a) {
        a.attester = attester;
        a.revocable = true;
        a.data = data;
    }

    /// The resolver accepts an attestation exactly when the attester holds the schema's role, never a different
    /// (higher or lower) one, for each of the three schemas.
    function testFuzz_resolverRequiresExactRole(uint8 roleSeed, uint8 kindSeed, address attester) public {
        vm.assume(attester != address(0) && attester != governor);
        IssuerRoleResolver.SchemaKind kind = IssuerRoleResolver.SchemaKind(bound(kindSeed, 0, 2));
        uint8 role = uint8(bound(roleSeed, 0, 3));
        vm.prank(governor);
        reg.setIssuer(scope, attester, VerifiablePolicyRegistry.Role(role));
        IssuerRoleResolver r = new IssuerRoleResolver(address(this), IIssuerRoles(address(reg)), kind);
        bytes memory data = kind == IssuerRoleResolver.SchemaKind.Conformance
            ? abi.encode(scope, "NIST SP 800-81r3", "r3", bytes32(0), uint64(1), uint64(2))
            : (
                kind == IssuerRoleResolver.SchemaKind.Deployment
                    ? abi.encode("giga-0001", scope, uint256(1), bytes32(0), uint64(1))
                    : abi.encode("giga-0001", scope, uint256(1), true, true, true, true, bytes32(0), uint64(1), uint64(2))
            );
        uint8 required = uint8(kind) + 1; // Deployment -> Operator (1), IndependentTest -> Reviewer (2), Conformance -> Auditor (3)
        assertEq(r.attest(_attestation(attester, data)), role == required);
    }

    /// A batch is accepted exactly when every attestation in it would be accepted on its own.
    function testFuzz_resolverBatchAllOrNothing(uint8 mask, uint8 sizeSeed) public {
        uint256 n = bound(sizeSeed, 1, 6);
        IssuerRoleResolver r =
            new IssuerRoleResolver(address(this), IIssuerRoles(address(reg)), IssuerRoleResolver.SchemaKind.IndependentTest);
        address reviewer = makeAddr("reviewer");
        address other = makeAddr("other");
        vm.startPrank(governor);
        reg.setIssuer(scope, reviewer, VerifiablePolicyRegistry.Role.Reviewer);
        reg.setIssuer(scope, other, VerifiablePolicyRegistry.Role.Operator);
        vm.stopPrank();
        bytes memory data = abi.encode("giga-0001", scope, uint256(1), true, true, true, true, bytes32(0), uint64(1), uint64(2));
        Attestation[] memory list = new Attestation[](n);
        uint256[] memory values = new uint256[](n);
        bool all = true;
        for (uint256 i = 0; i < n; i++) {
            bool ok = (mask >> i) & 1 == 1;
            list[i] = _attestation(ok ? reviewer : other, data);
            all = all && ok;
        }
        assertEq(r.multiAttest(list, values), all);
    }

    /// Any non-canonical offset of the first string, or a truncated head, is refused.
    function testFuzz_resolverRejectsNonCanonical(bytes32 s, uint256 offset, uint256 cut) public {
        IssuerRoleResolver r =
            new IssuerRoleResolver(address(this), IIssuerRoles(address(reg)), IssuerRoleResolver.SchemaKind.IndependentTest);
        bytes memory data = abi.encode("giga-0001", s, uint256(1), true, true, true, true, bytes32(0), uint64(1), uint64(2));
        vm.assume(offset != 0x140);
        bytes memory shifted = bytes.concat(bytes32(offset), _slice(data, 32, data.length));
        vm.expectRevert(IssuerRoleResolver.MalformedAttestation.selector);
        r.scopeOf(shifted);
        uint256 len = bound(cut, 0, 10 * 32 - 1);
        vm.expectRevert(IssuerRoleResolver.MalformedAttestation.selector);
        r.scopeOf(_slice(data, 0, len));
    }
}
