// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../src/VerifiablePolicyRegistry.sol";

/// @notice Drives the registry with random calls from random actors over several scopes, and checks every call
///         against an oracle written from the specification (docs/INTERFACES.md I2, white paper §3.3): a call the
///         specification accepts must succeed, and a call it refuses must revert. The oracle reads state, never the
///         contract's decision logic. A ghost model records what each scope must contain.
contract RegistryHandler is Test {
    VerifiablePolicyRegistry public immutable reg;
    address[] public actors;
    bytes32[] public scopeIds;
    bytes32[] public appealIds;

    uint256 constant CAP = 365 days;
    uint256 constant MAX_URI = 256;
    uint256 constant MAX_NAME = 128;
    VerifiablePolicyRegistry.AppealStatus constant NONE = VerifiablePolicyRegistry.AppealStatus.None;
    VerifiablePolicyRegistry.AppealStatus constant OPEN = VerifiablePolicyRegistry.AppealStatus.Open;
    VerifiablePolicyRegistry.AppealStatus constant ACCEPTED = VerifiablePolicyRegistry.AppealStatus.Accepted;
    VerifiablePolicyRegistry.AppealStatus constant REJECTED = VerifiablePolicyRegistry.AppealStatus.Rejected;

    // Oracle disagreements.
    uint256 public unexpectedSuccesses;
    uint256 public unexpectedReverts;
    string public lastDisagreement;

    // Ghost model.
    mapping(bytes32 => uint256) public ghostVersions;
    mapping(bytes32 => mapping(uint256 => bytes32)) public ghostVersionHash; // keccak of the whole stored version
    mapping(bytes32 => bytes32) public ghostAppealScope;
    mapping(bytes32 => VerifiablePolicyRegistry.AppealStatus) public ghostFinal;
    mapping(bytes32 => bytes32) public ghostResolution;
    bool public finalStateChanged;

    // Path counters, reported by the reachability test.
    uint256 public versionsPublished;
    uint256 public appealsAccepted;
    uint256 public appealsRejected;
    uint256 public handovers;
    uint256 public scopesCreated;

    constructor(VerifiablePolicyRegistry r, address[] memory a, bytes32[] memory s) {
        reg = r;
        actors = a;
        scopeIds = s;
    }

    // ------------------------------------------------------------------ views for the invariant contract

    function scopeCount() external view returns (uint256) {
        return scopeIds.length;
    }

    function appealCount() external view returns (uint256) {
        return appealIds.length;
    }

    function governorOf(bytes32 s) public view returns (address g) {
        (g,,) = reg.scopes(s);
    }

    function maxValidityOf(bytes32 s) public view returns (uint64 m) {
        (, m,) = reg.scopes(s);
    }

    // ------------------------------------------------------------------ helpers

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev The scope's governor half of the time (authorised path), otherwise any actor.
    function _caller(bytes32 s, uint256 seed) internal view returns (address) {
        return seed % 2 == 0 ? governorOf(s) : _actor(seed / 2);
    }

    function _scope(uint256 seed) internal view returns (bytes32) {
        return scopeIds[seed % scopeIds.length];
    }

    function _status(bytes32 id) internal view returns (VerifiablePolicyRegistry.AppealStatus st) {
        (, st,,,,) = reg.appeals(id);
    }

    function _check(bool expected, bool succeeded, string memory what) internal {
        if (succeeded && !expected) {
            unexpectedSuccesses++;
            lastDisagreement = what;
        } else if (!succeeded && expected) {
            unexpectedReverts++;
            lastDisagreement = what;
        }
    }

    function _uri(uint256 seed) internal pure returns (string memory) {
        uint256 k = seed % 8;
        if (k == 0) return string(new bytes(MAX_URI)); // exactly at the limit
        if (k == 1) return string(new bytes(MAX_URI + 1)); // just above
        return "ipfs://v";
    }

    /// @dev Records the first final state of each appeal and flags any later change of status or resolution.
    function _checkFinal() internal {
        for (uint256 i = 0; i < appealIds.length; i++) {
            bytes32 id = appealIds[i];
            (, VerifiablePolicyRegistry.AppealStatus st,,,, bytes32 resolution) = reg.appeals(id);
            if (ghostFinal[id] != NONE) {
                if (st != ghostFinal[id] || resolution != ghostResolution[id]) finalStateChanged = true;
            } else if (st == ACCEPTED || st == REJECTED) {
                ghostFinal[id] = st;
                ghostResolution[id] = resolution;
            }
        }
    }

    // ------------------------------------------------------------------ actions

    function createScope(uint256 actorSeed, uint256 nameSeed, uint64 maxValidity) external {
        address a = _actor(actorSeed);
        uint256 k = nameSeed % 6;
        string memory name = k == 0
            ? ""
            : (k == 1 ? string(new bytes(MAX_NAME + 1)) : (k == 2 ? string(new bytes(MAX_NAME)) : string(abi.encodePacked("scope-", vm.toString(k)))));
        uint256 mv = bound(maxValidity, 0, 400 days);
        if (nameSeed % 5 == 0) mv = CAP; // exactly at the cap
        if (nameSeed % 7 == 0) mv = CAP + 1; // just above
        bytes32 id = keccak256(abi.encode(a, name));
        (,, bool exists) = reg.scopes(id);
        bool expected = bytes(name).length > 0 && bytes(name).length <= MAX_NAME && mv > 0 && mv <= CAP && !exists;
        vm.prank(a);
        try reg.createScope(name, uint64(mv)) returns (bytes32 got) {
            _check(expected, true, "createScope");
            if (got != id) unexpectedSuccesses++;
            scopeIds.push(got);
            scopesCreated++;
        } catch {
            _check(expected, false, "createScope");
        }
    }

    function publish(uint256 scopeSeed, uint256 actorSeed, uint256 hSeed, uint64 validity, uint16 reason, uint256 appealSeed)
        external
    {
        bytes32 s = _scope(scopeSeed);
        address a = _caller(s, actorSeed);
        bytes32 h = hSeed % 16 == 0 ? bytes32(0) : keccak256(abi.encode(hSeed));
        uint64 mv = maxValidityOf(s);
        uint64 v = uint64(bound(validity, 0, uint256(mv) + 30 days));
        if (hSeed % 5 == 0) v = mv; // exactly the scope's maximum
        uint16 rc = uint16(bound(reason, 0, 7));
        bytes32 appeal;
        if (appealIds.length > 0 && appealSeed % 2 == 0) {
            appeal = appealIds[(appealSeed / 2) % appealIds.length];
            if (appealSeed % 8 != 0) rc = 3; // usually the matching reason code
        }
        string memory uri = _uri(appealSeed / 16);

        bool appealOk = appeal == bytes32(0) || (_status(appeal) == OPEN && ghostAppealScope[appeal] == s);
        bool expected = a == governorOf(s) && h != bytes32(0) && v > 0 && v <= mv && bytes(uri).length <= MAX_URI
            && rc >= 1 && rc <= 6 && ((rc == 3) == (appeal != bytes32(0))) && appealOk;
        uint256 before = reg.versionCount(s);

        vm.prank(a);
        try reg.publishPolicy(s, h, bytes32(0), uri, rc, v, appeal) returns (uint256 version) {
            _check(expected, true, "publishPolicy");
            VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(s, version);
            // the stored version is exactly what was published
            if (
                version != before + 1 || p.contentHash != h || p.reasonCode != rc || p.resolvesAppeal != appeal
                    || p.publishedAt != block.timestamp || p.expiresAt != block.timestamp + v
                    || keccak256(bytes(p.uri)) != keccak256(bytes(uri))
            ) unexpectedSuccesses++;
            ghostVersions[s] = version;
            ghostVersionHash[s][version] = keccak256(abi.encode(p));
            versionsPublished++;
            if (appeal != bytes32(0)) appealsAccepted++;
        } catch {
            _check(expected, false, "publishPolicy");
        }
        _checkFinal();
    }

    function fileAppeal(uint256 scopeSeed, uint256 actorSeed, uint256 docSeed) external {
        bytes32 s = _scope(scopeSeed);
        // a small pool of documents, so that refilings happen; occasionally the empty hash
        bytes32 doc = docSeed % 10 == 0 ? bytes32(0) : keccak256(abi.encode("doc", docSeed % 4));
        uint32 round = reg.appealRounds(keccak256(abi.encode(s, doc)));
        bytes32 latest = keccak256(abi.encode(s, doc, round));
        // a document can be filed if it never was, or if its latest round was rejected
        bool expected = doc != bytes32(0) && (round == 0 || _status(latest) == REJECTED);
        bytes32 expectedId = keccak256(abi.encode(s, doc, round + 1));
        address a = _actor(actorSeed);
        vm.prank(a);
        try reg.fileAppeal(s, doc) returns (bytes32 id) {
            _check(expected, true, "fileAppeal");
            if (id != expectedId) unexpectedSuccesses++;
            appealIds.push(id);
            ghostAppealScope[id] = s;
        } catch {
            _check(expected, false, "fileAppeal");
        }
        _checkFinal();
    }

    function rejectAppeal(uint256 actorSeed, uint256 idSeed, uint256 reasonSeed) external {
        if (appealIds.length == 0) return;
        bytes32 id = appealIds[idSeed % appealIds.length];
        bytes32 s = ghostAppealScope[id];
        address a = _caller(s, actorSeed);
        bytes32 reasonHash = reasonSeed % 8 == 0 ? bytes32(0) : keccak256(abi.encode(reasonSeed));
        bool expected = _status(id) == OPEN && a == governorOf(s) && reasonHash != bytes32(0);
        vm.prank(a);
        try reg.rejectAppeal(id, reasonHash) {
            _check(expected, true, "rejectAppeal");
            appealsRejected++;
        } catch {
            _check(expected, false, "rejectAppeal");
        }
        _checkFinal();
    }

    function setIssuer(uint256 scopeSeed, uint256 actorSeed, uint256 targetSeed, uint8 role) external {
        bytes32 s = _scope(scopeSeed);
        address a = _caller(s, actorSeed);
        address pending = reg.pendingGovernor(s);
        address target = targetSeed % 9 == 0
            ? address(0)
            : ((pending != address(0) && targetSeed % 2 == 0) ? pending : _actor(targetSeed));
        VerifiablePolicyRegistry.Role r = VerifiablePolicyRegistry.Role(bound(role, 0, 3));
        bool expected = a == governorOf(s) && target != address(0) && target != a
            && !(r != VerifiablePolicyRegistry.Role.None && target == pending);
        vm.prank(a);
        try reg.setIssuer(s, target, r) {
            _check(expected, true, "setIssuer");
            if (reg.issuerRole(s, target) != r) unexpectedSuccesses++;
        } catch {
            _check(expected, false, "setIssuer");
        }
    }

    function proposeGovernor(uint256 scopeSeed, uint256 actorSeed, uint256 targetSeed, bool cancel) external {
        bytes32 s = _scope(scopeSeed);
        address a = _caller(s, actorSeed);
        address target = cancel ? address(0) : _actor(targetSeed);
        bool expected = a == governorOf(s) && reg.issuerRole(s, target) == VerifiablePolicyRegistry.Role.None;
        vm.prank(a);
        try reg.proposeGovernor(s, target) {
            _check(expected, true, "proposeGovernor");
            if (reg.pendingGovernor(s) != target) unexpectedSuccesses++;
        } catch {
            _check(expected, false, "proposeGovernor");
        }
    }

    function acceptGovernor(uint256 scopeSeed, uint256 actorSeed) external {
        bytes32 s = _scope(scopeSeed);
        address pending = reg.pendingGovernor(s);
        address a = (pending != address(0) && actorSeed % 2 == 0) ? pending : _actor(actorSeed / 2);
        bool expected =
            pending != address(0) && a == pending && reg.issuerRole(s, pending) == VerifiablePolicyRegistry.Role.None;
        vm.prank(a);
        try reg.acceptGovernor(s) {
            _check(expected, true, "acceptGovernor");
            if (governorOf(s) != pending || reg.pendingGovernor(s) != address(0)) unexpectedSuccesses++;
            handovers++;
        } catch {
            _check(expected, false, "acceptGovernor");
        }
    }

    /// @dev Half of the time, land exactly on (or one second before) the expiry of a scope's latest version.
    function warp(uint256 secs, uint256 scopeSeed) external {
        bytes32 s = _scope(scopeSeed);
        uint256 n = reg.versionCount(s);
        if (secs % 2 == 0 && n > 0) {
            uint64 e = reg.getVersion(s, n).expiresAt;
            uint256 target = (secs / 2) % 2 == 0 ? e : uint256(e) - 1;
            if (target > block.timestamp) vm.warp(target);
            return;
        }
        vm.warp(block.timestamp + bound(secs, 0, 30 days));
    }
}

/// @title Registry invariants
/// @notice Each invariant restates a property of white paper §3.3 or docs/INTERFACES.md I2 and must hold after any
///         sequence of calls by any actor, over several scopes.
contract RegistryInvariants is Test {
    VerifiablePolicyRegistry reg;
    RegistryHandler handler;

    function setUp() public {
        vm.warp(20767 days); // 2026-11-10, so timestamps are realistic
        reg = new VerifiablePolicyRegistry();
        address[] memory actors = new address[](5);
        for (uint256 i = 0; i < actors.length; i++) actors[i] = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
        bytes32[] memory scopes = new bytes32[](2);
        vm.prank(actors[0]);
        scopes[0] = reg.createScope("giga:XX:primary", 90 days);
        vm.prank(actors[1]);
        scopes[1] = reg.createScope("giga:YY:primary", 30 days);
        handler = new RegistryHandler(reg, actors, scopes);
        targetContract(address(handler));
    }

    function _scope(uint256 i) internal view returns (bytes32) {
        return handler.scopeIds(i);
    }

    /// Every call succeeds exactly when the specification says it should: no unauthorised or invalid call is
    /// accepted (P3, P4, reason codes, appeals, roles), and no valid call is refused.
    function invariant_oracleAgrees() public view {
        assertEq(handler.unexpectedSuccesses(), 0, handler.lastDisagreement());
        assertEq(handler.unexpectedReverts(), 0, handler.lastDisagreement());
    }

    /// P2 · Versions are append-only: their number equals the model and no stored field of a past version changes.
    function invariant_versionsImmutable() public view {
        for (uint256 i = 0; i < handler.scopeCount(); i++) {
            bytes32 s = _scope(i);
            uint256 n = reg.versionCount(s);
            assertEq(n, handler.ghostVersions(s));
            for (uint256 v = 1; v <= n; v++) {
                assertEq(keccak256(abi.encode(reg.getVersion(s, v))), handler.ghostVersionHash(s, v));
            }
        }
    }

    /// P4 · Every scope's maximum validity is at most 365 days, and every version expires within it.
    function invariant_boundedDuration() public view {
        for (uint256 i = 0; i < handler.scopeCount(); i++) {
            bytes32 s = _scope(i);
            uint64 mv = handler.maxValidityOf(s);
            assertGt(mv, 0);
            assertLe(mv, 365 days);
            uint256 n = reg.versionCount(s);
            for (uint256 v = 1; v <= n; v++) {
                VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(s, v);
                assertGt(p.expiresAt, p.publishedAt);
                assertLe(p.expiresAt - p.publishedAt, mv);
            }
        }
    }

    /// P1/P4 · currentPolicy returns the latest version, in force exactly while block.timestamp < expiresAt.
    function invariant_currentPolicyInForce() public view {
        for (uint256 i = 0; i < handler.scopeCount(); i++) {
            bytes32 s = _scope(i);
            uint256 n = reg.versionCount(s);
            (uint256 version, VerifiablePolicyRegistry.PolicyVersion memory p, bool inForce) = reg.currentPolicy(s);
            assertEq(version, n);
            if (n == 0) {
                assertFalse(inForce);
            } else {
                assertEq(keccak256(abi.encode(p)), keccak256(abi.encode(reg.getVersion(s, n))));
                assertEq(inForce, block.timestamp < p.expiresAt);
            }
        }
    }

    /// Reason codes are in 1..6, and code 3 is used if and only if the version resolves an appeal.
    function invariant_reasonCodes() public view {
        for (uint256 i = 0; i < handler.scopeCount(); i++) {
            bytes32 s = _scope(i);
            uint256 n = reg.versionCount(s);
            for (uint256 v = 1; v <= n; v++) {
                VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(s, v);
                assertGe(p.reasonCode, 1);
                assertLe(p.reasonCode, 6);
                assertEq(p.reasonCode == 3, p.resolvesAppeal != bytes32(0));
            }
        }
    }

    /// P5 · An appeal keeps the scope it was filed against; it is accepted only by exactly one version of that
    ///      scope, whose content hash is its resolution, and by no version of another scope; a rejection carries
    ///      a reason; final states and resolutions never change.
    function invariant_appealResolution() public view {
        assertFalse(handler.finalStateChanged());
        for (uint256 i = 0; i < handler.appealCount(); i++) {
            bytes32 id = handler.appealIds(i);
            (bytes32 s, VerifiablePolicyRegistry.AppealStatus st,,,, bytes32 resolution) = reg.appeals(id);
            assertEq(s, handler.ghostAppealScope(id));
            uint256 resolvers;
            for (uint256 j = 0; j < handler.scopeCount(); j++) {
                bytes32 other = _scope(j);
                uint256 n = reg.versionCount(other);
                for (uint256 v = 1; v <= n; v++) {
                    VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(other, v);
                    if (p.resolvesAppeal == id) {
                        assertEq(other, s);
                        assertEq(p.contentHash, resolution);
                        resolvers++;
                    }
                }
            }
            if (st == VerifiablePolicyRegistry.AppealStatus.Accepted) {
                assertEq(resolvers, 1);
            } else {
                assertEq(resolvers, 0);
                if (st == VerifiablePolicyRegistry.AppealStatus.Rejected) assertTrue(resolution != bytes32(0));
                else assertEq(resolution, bytes32(0));
            }
        }
    }

    /// Separation of roles: neither the governor nor the pending governor of any scope holds an issuer role.
    function invariant_governorHoldsNoRole() public view {
        for (uint256 i = 0; i < handler.scopeCount(); i++) {
            bytes32 s = _scope(i);
            assertEq(uint8(reg.issuerRole(s, handler.governorOf(s))), 0);
            address pending = reg.pendingGovernor(s);
            if (pending != address(0)) assertEq(uint8(reg.issuerRole(s, pending)), 0);
        }
    }

    /// Reachability: the handler reaches every state the invariants talk about (versions, accepted and rejected
    /// appeals, refilings, handovers, new scopes, expiry instants), so no invariant passes vacuously. Even actor
    /// seeds call as the scope's governor.
    function test_handlerReachesEveryState() public {
        handler.publish(0, 0, 1, 30 days, 1, 1);
        handler.fileAppeal(0, 3, 1);
        handler.fileAppeal(0, 4, 2);
        handler.rejectAppeal(0, 1, 1);
        handler.fileAppeal(0, 3, 2); // refiling after a rejection: round 2
        handler.publish(0, 0, 3, 30 days, 3, 0); // appealSeed 0 -> first appeal, reason 3
        handler.fileAppeal(0, 3, 1); // refiling an accepted document must fail
        handler.setIssuer(0, 0, 2, 2);
        handler.proposeGovernor(0, 0, 1, false);
        handler.acceptGovernor(0, 0);
        handler.createScope(2, 3, 60 days);
        handler.warp(0, 0); // to the expiry instant of scope 0's latest version
        assertGe(handler.versionsPublished(), 2);
        assertEq(handler.appealsAccepted(), 1);
        assertEq(handler.appealsRejected(), 1);
        assertEq(handler.handovers(), 1);
        assertEq(handler.scopesCreated(), 1);
        (,, bool inForce) = reg.currentPolicy(_scope(0));
        assertFalse(inForce); // exactly at expiresAt the version is no longer in force
        invariant_oracleAgrees();
        invariant_versionsImmutable();
        invariant_appealResolution();
        invariant_currentPolicyInForce();
        invariant_governorHoldsNoRole();
    }
}
