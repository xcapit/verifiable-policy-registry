// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../src/VerifiablePolicyRegistry.sol";

/// @notice Drives the registry with random sequences of calls from random actors, including unauthorised ones,
///         and keeps a ghost model of what the registry must contain.
contract RegistryHandler is Test {
    VerifiablePolicyRegistry public immutable reg;
    bytes32 public immutable scope;
    address[] public actors;

    // Ghost model.
    uint256 public ghostVersions;
    mapping(uint256 => bytes32) public ghostHash;
    bytes32[] public appealIds;
    mapping(bytes32 => VerifiablePolicyRegistry.AppealStatus) public ghostFinal;
    mapping(bytes32 => bytes32) public ghostResolution;
    uint256 public unauthorisedSuccesses;
    bool public finalStatusChanged;

    constructor(VerifiablePolicyRegistry r, bytes32 s, address[] memory a) {
        reg = r;
        scope = s;
        actors = a;
    }

    function governor() public view returns (address g) {
        (g,,) = reg.scopes(scope);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function appealCount() external view returns (uint256) {
        return appealIds.length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Records the first final status and resolution of each appeal and flags any later change of either.
    function _checkFinal() private {
        for (uint256 i = 0; i < appealIds.length; i++) {
            bytes32 id = appealIds[i];
            (, VerifiablePolicyRegistry.AppealStatus st,,,, bytes32 resolution) = reg.appeals(id);
            VerifiablePolicyRegistry.AppealStatus seen = ghostFinal[id];
            if (seen != VerifiablePolicyRegistry.AppealStatus.None) {
                if (st != seen || resolution != ghostResolution[id]) finalStatusChanged = true;
            } else if (st == VerifiablePolicyRegistry.AppealStatus.Accepted || st == VerifiablePolicyRegistry.AppealStatus.Rejected) {
                ghostFinal[id] = st;
                ghostResolution[id] = resolution;
            }
        }
    }

    function publish(uint256 actorSeed, bytes32 h, uint64 validity, uint16 reason, uint256 appealSeed) external {
        address a = _actor(actorSeed);
        address gov = governor();
        // Mostly valid inputs, so that versions and acceptances actually happen; invalid ones are still drawn.
        validity = uint64(bound(validity, 0, 120 days));
        reason = uint16(bound(reason, 0, 7));
        bytes32 appeal;
        if (appealIds.length > 0 && appealSeed % 2 == 0) {
            appeal = appealIds[(appealSeed / 2) % appealIds.length];
            if (appealSeed % 8 != 0) reason = 3; // usually the matching reason code
        }
        vm.prank(a);
        try reg.publishPolicy(scope, h, bytes32(0), "ipfs://v", reason, validity, appeal) returns (uint256 v) {
            if (a != gov) unauthorisedSuccesses++;
            ghostVersions = v;
            ghostHash[v] = h;
        } catch {}
        _checkFinal();
    }

    function fileAppeal(uint256 actorSeed, bytes32 doc) external {
        vm.prank(_actor(actorSeed));
        try reg.fileAppeal(scope, doc) returns (bytes32 id) {
            appealIds.push(id);
        } catch {}
        _checkFinal();
    }

    function rejectAppeal(uint256 actorSeed, uint256 idSeed, bytes32 reasonHash) external {
        if (appealIds.length == 0) return;
        address a = _actor(actorSeed);
        address gov = governor();
        vm.prank(a);
        try reg.rejectAppeal(appealIds[idSeed % appealIds.length], reasonHash) {
            if (a != gov) unauthorisedSuccesses++;
        } catch {}
        _checkFinal();
    }

    function setIssuer(uint256 actorSeed, uint256 targetSeed, uint8 role) external {
        address a = _actor(actorSeed);
        address gov = governor();
        // Half of the time, target the pending governor: the state the role-separation invariant is about.
        address pending = reg.pendingGovernor(scope);
        address target = (pending != address(0) && targetSeed % 2 == 0) ? pending : _actor(targetSeed);
        vm.prank(a);
        try reg.setIssuer(scope, target, VerifiablePolicyRegistry.Role(bound(role, 0, 3))) {
            if (a != gov) unauthorisedSuccesses++;
        } catch {}
    }

    function proposeGovernor(uint256 actorSeed, uint256 targetSeed, bool cancel) external {
        address a = _actor(actorSeed);
        address gov = governor();
        vm.prank(a);
        try reg.proposeGovernor(scope, cancel ? address(0) : _actor(targetSeed)) {
            if (a != gov) unauthorisedSuccesses++;
        } catch {}
    }

    function acceptGovernor(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        address pending = reg.pendingGovernor(scope);
        vm.prank(a);
        try reg.acceptGovernor(scope) {
            if (a != pending) unauthorisedSuccesses++;
        } catch {}
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 30 days));
    }
}

/// @title Registry invariants
/// @notice Each invariant restates a property of white paper §3.3 or of docs/INTERFACES.md I2 and must hold after
///         any sequence of calls by any actor.
contract RegistryInvariants is Test {
    VerifiablePolicyRegistry reg;
    RegistryHandler handler;
    bytes32 scope;
    uint64 constant MAX_VALIDITY = 90 days;

    function setUp() public {
        vm.warp(20767 days); // 2026-11-10, so timestamps are realistic
        reg = new VerifiablePolicyRegistry();
        address[] memory actors = new address[](5);
        for (uint256 i = 0; i < actors.length; i++) actors[i] = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
        vm.prank(actors[0]);
        scope = reg.createScope("giga:XX:primary", MAX_VALIDITY);
        handler = new RegistryHandler(reg, scope, actors);
        targetContract(address(handler));
    }

    /// Reachability: the handler can drive the registry into every state the invariants talk about, so the
    /// invariants are not vacuous. Actor 0 is the governor; seeds are chosen to hit the success paths.
    function test_handlerReachesEveryState() public {
        handler.publish(0, keccak256("v1"), 30 days, 1, 1);
        assertEq(handler.ghostVersions(), 1);
        handler.fileAppeal(3, keccak256("doc-a"));
        handler.fileAppeal(4, keccak256("doc-b"));
        assertEq(handler.appealCount(), 2);
        handler.rejectAppeal(0, 1, keccak256("reasons"));
        handler.publish(0, keccak256("v2"), 30 days, 3, 0); // appealSeed 0 -> appeal 0, reason 3
        assertEq(handler.ghostVersions(), 2);
        (, VerifiablePolicyRegistry.AppealStatus a,,,,) = reg.appeals(handler.appealIds(0));
        (, VerifiablePolicyRegistry.AppealStatus b,,,,) = reg.appeals(handler.appealIds(1));
        assertEq(uint8(a), uint8(VerifiablePolicyRegistry.AppealStatus.Accepted));
        assertEq(uint8(b), uint8(VerifiablePolicyRegistry.AppealStatus.Rejected));
        handler.setIssuer(0, 2, 2);
        assertEq(uint8(reg.issuerRole(scope, handler.actors(2))), 2);
        handler.proposeGovernor(0, 1, false);
        handler.acceptGovernor(1);
        assertEq(handler.governor(), handler.actors(1));
        assertEq(handler.unauthorisedSuccesses(), 0);
        invariant_versionsAppendOnly();
        invariant_appealResolution();
        invariant_governorHoldsNoRole();
    }

    /// P2 · Versions are append-only: their number only grows and a stored version never changes.
    function invariant_versionsAppendOnly() public view {
        uint256 n = reg.versionCount(scope);
        assertEq(n, handler.ghostVersions());
        for (uint256 v = 1; v <= n; v++) {
            assertEq(reg.getVersion(scope, v).contentHash, handler.ghostHash(v));
        }
    }

    /// P4 · Every version expires, within the scope's maximum validity, itself capped at 365 days.
    function invariant_boundedDuration() public view {
        (, uint64 maxValidity,) = reg.scopes(scope);
        assertLe(maxValidity, reg.MAX_VALIDITY_CAP());
        uint256 n = reg.versionCount(scope);
        for (uint256 v = 1; v <= n; v++) {
            VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(scope, v);
            assertGt(p.expiresAt, p.publishedAt);
            assertLe(p.expiresAt - p.publishedAt, maxValidity);
        }
    }

    /// Reason codes are in 1..6, and code 3 is used if and only if the version resolves an appeal.
    function invariant_reasonCodes() public view {
        uint256 n = reg.versionCount(scope);
        for (uint256 v = 1; v <= n; v++) {
            VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(scope, v);
            assertGe(p.reasonCode, 1);
            assertLe(p.reasonCode, reg.MAX_REASON_CODE());
            assertEq(p.reasonCode == reg.REASON_APPEAL_ACCEPTED(), p.resolvesAppeal != bytes32(0));
        }
    }

    /// P5 · An accepted appeal is accepted only by a version of its own scope that names it, and its resolution is
    ///      that version's content hash; a rejection always carries a reason. Final states never change.
    function invariant_appealResolution() public view {
        assertFalse(handler.finalStatusChanged());
        uint256 m = handler.appealCount();
        uint256 n = reg.versionCount(scope);
        for (uint256 i = 0; i < m; i++) {
            bytes32 id = handler.appealIds(i);
            (bytes32 s, VerifiablePolicyRegistry.AppealStatus st,,,, bytes32 resolution) = reg.appeals(id);
            assertEq(s, scope);
            if (st == VerifiablePolicyRegistry.AppealStatus.Accepted) {
                bool found;
                for (uint256 v = 1; v <= n; v++) {
                    VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(scope, v);
                    if (p.resolvesAppeal == id) {
                        assertFalse(found); // resolved by exactly one version
                        found = true;
                        assertEq(p.contentHash, resolution);
                    }
                }
                assertTrue(found);
            } else if (st == VerifiablePolicyRegistry.AppealStatus.Rejected) {
                assertTrue(resolution != bytes32(0));
            } else {
                assertEq(resolution, bytes32(0));
            }
        }
    }

    /// Separation of roles: neither the governor nor the pending governor ever holds an issuer role.
    function invariant_governorHoldsNoRole() public view {
        assertEq(uint8(reg.issuerRole(scope, handler.governor())), uint8(VerifiablePolicyRegistry.Role.None));
        address pending = reg.pendingGovernor(scope);
        if (pending != address(0)) {
            assertEq(uint8(reg.issuerRole(scope, pending)), uint8(VerifiablePolicyRegistry.Role.None));
        }
    }

    /// Only the current governor (or, for acceptGovernor, the pending governor) can change governed state.
    function invariant_onlyGovernorMutates() public view {
        assertEq(handler.unauthorisedSuccesses(), 0);
    }
}
