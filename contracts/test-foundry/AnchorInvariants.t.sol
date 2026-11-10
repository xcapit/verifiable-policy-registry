// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../src/VerifiablePolicyRegistry.sol";
import {MetricsAnchor, IPolicyRegistry} from "../src/MetricsAnchor.sol";

/// @notice Drives the anchor with random commits, empty markers, corrections, publisher changes, governor
///         rotations in the registry and time jumps (biased to day boundaries), from the governors, the publishers
///         and a stranger. Every call is checked against an oracle written from the specification
///         (docs/INTERFACES.md I7): a call the specification accepts must succeed, and one it refuses must revert.
contract AnchorHandler is Test {
    VerifiablePolicyRegistry public immutable reg;
    MetricsAnchor public immutable anchor;
    bytes32 public immutable scope;
    address[] public actors; // 0, 1: governors in turn; 2, 3: publishers; 4: stranger

    uint32 constant NO_LAG_LIMIT = type(uint32).max;
    uint256 constant MAX_URI = 256;
    string constant UNIT = "giga-0001";
    string constant CATEGORY = "malware";
    uint256 constant COUNT = 25;

    struct Ghost {
        bool written;
        bytes32 root;
        uint32 revision;
        bool empty;
        uint64 committedAt;
        bytes32 uriHash;
    }

    uint32[] public touchedDays;
    mapping(uint32 => Ghost) internal ghost;

    uint256 public unexpectedSuccesses;
    uint256 public unexpectedReverts;
    string public lastDisagreement;

    uint256 public commits;
    uint256 public empties;
    uint256 public corrections;
    uint256 public rotations;

    constructor(VerifiablePolicyRegistry r, MetricsAnchor a, bytes32 s, address[] memory act) {
        reg = r;
        anchor = a;
        scope = s;
        actors = act;
    }

    // ------------------------------------------------------------------ independent reference model

    /// @dev Leaf of the fixed row, computed from the specification (I6), not by calling the contract.
    function knownLeaf(uint32 day) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes1(0x00), day, COUNT, uint16(bytes(UNIT).length), bytes(UNIT), uint16(bytes(CATEGORY).length), bytes(CATEGORY)
            )
        );
    }

    function dayCount() external view returns (uint256) {
        return touchedDays.length;
    }

    function ghostOf(uint32 day) external view returns (Ghost memory) {
        return ghost[day];
    }

    function governor() public view returns (address g) {
        (g,,) = reg.scopes(scope);
    }

    // ------------------------------------------------------------------ helpers

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
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

    function _today() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @dev Half of the time an exact boundary (the oldest day the window allows, the first it refuses, yesterday,
    ///      today), otherwise any day from 40 days back to 2 days ahead.
    function _day(uint256 seed) internal view returns (uint32) {
        uint256 t = _today();
        if (seed % 2 == 0) {
            uint256 k = (seed / 2) % 4;
            uint32 lag = anchor.maxLagDays(scope);
            if (k < 2 && lag != 0 && lag != NO_LAG_LIMIT && lag + 1 <= t) return uint32(t - lag - k);
            return uint32(t - (k % 2));
        }
        return uint32(bound(seed, t - 40, t + 2));
    }

    function _uri(uint256 seed) internal pure returns (string memory) {
        uint256 k = seed % 8;
        if (k == 0) return string(new bytes(MAX_URI));
        if (k == 1) return string(new bytes(MAX_URI + 1));
        return "ipfs://d";
    }

    /// @dev Specification of a publisher write: the publisher, a day that has ended, within the window, never
    ///      written before.
    function _publishable(address a, uint32 day) internal view returns (bool) {
        address p = anchor.publisher(scope);
        uint256 t = _today();
        uint32 lag = anchor.maxLagDays(scope);
        bool inWindow = lag == NO_LAG_LIMIT || uint256(day) + lag >= t;
        return p != address(0) && a == p && uint256(day) < t && inWindow && !ghost[day].written;
    }

    function _record(uint32 day, bytes32 root, bool empty, string memory uri) internal {
        touchedDays.push(day);
        ghost[day] = Ghost(true, root, 0, empty, uint64(block.timestamp), keccak256(bytes(uri)));
    }

    // ------------------------------------------------------------------ actions

    function commitRoot(uint256 actorSeed, uint256 daySeed, uint256 rootSeed) external {
        address p = anchor.publisher(scope);
        address a = (p != address(0) && actorSeed % 2 == 0) ? p : _actor(actorSeed / 2);
        uint32 day = _day(daySeed);
        uint256 k = rootSeed % 8;
        bytes32 root = k == 0 ? bytes32(0) : (k < 4 ? knownLeaf(day) : keccak256(abi.encode(rootSeed)));
        string memory uri = _uri(rootSeed / 8);
        bool expected = _publishable(a, day) && root != bytes32(0) && bytes(uri).length <= MAX_URI;
        vm.prank(a);
        try anchor.commitRoot(scope, day, root, uri) {
            _check(expected, true, "commitRoot");
            if (expected) {
                _record(day, root, false, uri);
                commits++;
            }
        } catch {
            _check(expected, false, "commitRoot");
        }
    }

    function markEmpty(uint256 actorSeed, uint256 daySeed) external {
        address p = anchor.publisher(scope);
        address a = (p != address(0) && actorSeed % 2 == 0) ? p : _actor(actorSeed / 2);
        uint32 day = _day(daySeed);
        bool expected = _publishable(a, day);
        vm.prank(a);
        try anchor.markEmpty(scope, day) {
            _check(expected, true, "markEmpty");
            if (expected) {
                _record(day, bytes32(0), true, "");
                empties++;
            }
        } catch {
            _check(expected, false, "markEmpty");
        }
    }

    function correctRoot(uint256 actorSeed, uint256 daySeed, uint256 rootSeed, uint256 reasonSeed) external {
        address g = governor();
        address a = actorSeed % 2 == 0 ? g : _actor(actorSeed / 2);
        // usually a day that was written, sometimes any day
        uint32 day = (touchedDays.length > 0 && daySeed % 4 != 0) ? touchedDays[daySeed % touchedDays.length] : _day(daySeed);
        Ghost memory gh = ghost[day];
        uint256 k = rootSeed % 6;
        bytes32 newRoot = k == 0 ? bytes32(0) : (k == 1 ? gh.root : (k < 4 ? knownLeaf(day) : keccak256(abi.encode(rootSeed))));
        bytes32 reasonHash = reasonSeed % 8 == 0 ? bytes32(0) : keccak256(abi.encode(reasonSeed));
        string memory uri = _uri(reasonSeed / 8);
        bool expected = a == g && gh.written && newRoot != gh.root && reasonHash != bytes32(0) && bytes(uri).length <= MAX_URI;
        vm.prank(a);
        try anchor.correctRoot(scope, day, newRoot, uri, reasonHash) {
            _check(expected, true, "correctRoot");
            if (expected) {
                Ghost storage s = ghost[day];
                s.root = newRoot;
                s.empty = newRoot == bytes32(0);
                s.revision += 1;
                s.uriHash = keccak256(bytes(uri)); // committedAt deliberately unchanged
                corrections++;
            }
        } catch {
            _check(expected, false, "correctRoot");
        }
    }

    function setPublisher(uint256 actorSeed, uint256 pubSeed, uint32 lag, uint256 mode) external {
        address g = governor();
        address a = actorSeed % 2 == 0 ? g : _actor(actorSeed / 2);
        uint256 m = mode % 6;
        address p = m == 0 ? address(0) : actors[2 + pubSeed % 2];
        uint32 l;
        if (m == 0) l = 0; // revoke
        else if (m == 1) l = NO_LAG_LIMIT;
        else if (m == 2) l = 0; // invalid: a publisher without a window
        else l = uint32(bound(lag, 1, 60));
        if (m == 5 && pubSeed % 2 == 0) p = address(0); // invalid: revocation with a window
        bool expected = a == g && ((p == address(0)) == (l == 0));
        vm.prank(a);
        try anchor.setPublisher(scope, p, l) {
            _check(expected, true, "setPublisher");
            if (anchor.publisher(scope) != p || anchor.maxLagDays(scope) != l) unexpectedSuccesses++;
        } catch {
            _check(expected, false, "setPublisher");
        }
    }

    /// @dev Hands the scope over to the other governor address in the registry (a valid two-step handover).
    function rotateGovernor() external {
        address g = governor();
        address next = g == actors[0] ? actors[1] : actors[0];
        vm.prank(g);
        reg.proposeGovernor(scope, next);
        vm.prank(next);
        reg.acceptGovernor(scope);
        rotations++;
    }

    /// @dev Half of the time, land one second before or exactly on the next UTC midnight.
    function warp(uint256 secs) external {
        if (secs % 2 == 0) {
            uint256 midnight = (_today() + 1) * 1 days;
            vm.warp((secs / 2) % 2 == 0 ? midnight : midnight - 1);
            return;
        }
        vm.warp(block.timestamp + bound(secs, 0, 3 days));
    }
}

/// @title Metrics anchor invariants
/// @notice Restates the anchoring rules of docs/INTERFACES.md I7 and white paper §5.3.
contract AnchorInvariants is Test {
    VerifiablePolicyRegistry reg;
    MetricsAnchor anchor;
    AnchorHandler handler;
    bytes32 scope;

    function setUp() public {
        vm.warp(20767 days); // 2026-11-10
        address[] memory actors = new address[](5);
        actors[0] = makeAddr("governor-a");
        actors[1] = makeAddr("governor-b");
        actors[2] = makeAddr("publisher-a");
        actors[3] = makeAddr("publisher-b");
        actors[4] = makeAddr("stranger");
        reg = new VerifiablePolicyRegistry();
        vm.prank(actors[0]);
        scope = reg.createScope("giga:XX:primary", 90 days);
        anchor = new MetricsAnchor(IPolicyRegistry(address(reg)));
        vm.prank(actors[0]);
        anchor.setPublisher(scope, actors[2], 7);
        handler = new AnchorHandler(reg, anchor, scope, actors);
        targetContract(address(handler));
    }

    /// Every call succeeds exactly when the specification says it should: only the publisher writes, once per
    /// day, only ended days within the window; only the current governor corrects and appoints; no valid call
    /// is refused.
    function invariant_oracleAgrees() public view {
        assertEq(handler.unexpectedSuccesses(), 0, handler.lastDisagreement());
        assertEq(handler.unexpectedReverts(), 0, handler.lastDisagreement());
    }

    /// The stored state of every written day equals the model: root, emptiness, revision, dataset URI, and a
    /// commit time that corrections never change.
    function invariant_daysMatchModel() public view {
        uint256 n = handler.dayCount();
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            MetricsAnchor.Commitment memory c = anchor.getCommitment(scope, day);
            AnchorHandler.Ghost memory g = handler.ghostOf(day);
            assertEq(c.root, g.root);
            assertEq(c.empty, g.empty);
            assertEq(c.revision, g.revision);
            assertEq(c.committedAt, g.committedAt);
            assertEq(keccak256(bytes(c.datasetUri)), g.uriHash);
        }
    }

    /// A day is empty exactly when its root is zero, and it was first written only after it ended.
    function invariant_committedDaysWellFormed() public view {
        uint256 n = handler.dayCount();
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            MetricsAnchor.Commitment memory c = anchor.getCommitment(scope, day);
            assertEq(c.empty, c.root == bytes32(0));
            assertGe(uint256(c.committedAt), (uint256(day) + 1) * 1 days);
        }
    }

    /// verifyRow agrees with an independent model: the fixed row verifies against a day exactly when that day's
    /// current root is the row's leaf (a one-row release) and the day is not empty; a correction to empty
    /// therefore revokes a previously valid row.
    function invariant_verifyRowMatchesModel() public view {
        uint256 n = handler.dayCount();
        bytes32[] memory proof = new bytes32[](0);
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            AnchorHandler.Ghost memory g = handler.ghostOf(day);
            bool expected = !g.empty && g.root == handler.knownLeaf(day);
            assertEq(anchor.verifyRow(scope, day, "giga-0001", "malware", 25, proof), expected);
        }
        assertEq(anchor.today(), block.timestamp / 1 days);
    }

    /// Reachability: the handler reaches committed, empty and corrected days (including root -> empty -> root),
    /// a day written at a window boundary, governor rotations and publisher changes, so no invariant passes
    /// vacuously. Even actor seeds call as the publisher (writes) or the governor (corrections).
    function test_handlerReachesEveryState() public {
        uint256 t = block.timestamp / 1 days;
        handler.commitRoot(0, 2, 1); // daySeed 2 -> k=1: first refused day; rootSeed 1 -> known leaf
        handler.commitRoot(0, 0, 1); // daySeed 0 -> k=0: oldest allowed day (t - 7)
        handler.markEmpty(0, 4); // daySeed 4 -> k=2: today -> refused (not closed)
        handler.markEmpty(0, 6); // daySeed 6 -> k=3: yesterday
        assertEq(handler.commits(), 1);
        assertEq(handler.empties(), 1);
        uint32 oldest = uint32(t - 7);
        assertTrue(handler.ghostOf(oldest).written);
        bytes32[] memory proof = new bytes32[](0);
        assertTrue(anchor.verifyRow(scope, oldest, "giga-0001", "malware", 25, proof));
        handler.correctRoot(0, 1, 0, 1); // touched day 1 % 2 -> yesterday (empty) ... to root 0: no change -> refused
        handler.correctRoot(0, 1, 2, 1); // yesterday: empty -> known leaf
        handler.correctRoot(0, 2, 0, 1); // oldest day: known leaf -> empty
        assertEq(handler.corrections(), 2);
        assertFalse(anchor.verifyRow(scope, oldest, "giga-0001", "malware", 25, proof));
        handler.rotateGovernor();
        handler.correctRoot(1, 2, 2, 1); // the former governor (odd seed -> actor 0) can no longer correct
        assertEq(handler.corrections(), 2);
        handler.setPublisher(0, 1, 3, 3); // new governor appoints publisher-b with a 3-day window
        assertEq(anchor.publisher(scope), handler.actors(3));
        handler.warp(0);
        assertEq(handler.rotations(), 1);
        invariant_oracleAgrees();
        invariant_daysMatchModel();
        invariant_committedDaysWellFormed();
        invariant_verifyRowMatchesModel();
    }
}
