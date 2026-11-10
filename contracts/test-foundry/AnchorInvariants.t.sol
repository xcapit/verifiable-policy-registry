// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../src/VerifiablePolicyRegistry.sol";
import {MetricsAnchor, IPolicyRegistry} from "../src/MetricsAnchor.sol";

/// @notice Drives the anchor with random commits, empty markers, corrections, publisher changes and time jumps,
///         from the governor, the publisher and a stranger, and keeps a ghost model of every touched day.
contract AnchorHandler is Test {
    VerifiablePolicyRegistry public immutable reg;
    MetricsAnchor public immutable anchor;
    bytes32 public immutable scope;
    address public immutable governor;
    address public immutable publisher;
    address public immutable stranger;

    struct Ghost {
        bytes32 root;
        uint32 revision;
        bool empty;
    }

    uint32[] public touchedDays;
    mapping(uint32 => bool) public touched;
    mapping(uint32 => Ghost) internal ghost;
    uint256 public unauthorisedSuccesses;
    uint256 public openDayAnchored; // publisher writes for a day that had not ended
    uint256 public outsideWindowAnchored; // publisher writes older than the back-fill window
    uint256 public rewrites; // publisher writes to a day that was already written

    constructor(VerifiablePolicyRegistry r, MetricsAnchor a, bytes32 s, address g, address p, address x) {
        reg = r;
        anchor = a;
        scope = s;
        governor = g;
        publisher = p;
        stranger = x;
    }

    function dayCount() external view returns (uint256) {
        return touchedDays.length;
    }

    function ghostOf(uint32 day) external view returns (Ghost memory) {
        return ghost[day];
    }

    function _actor(uint256 seed) private view returns (address) {
        uint256 k = seed % 3;
        return k == 0 ? governor : (k == 1 ? publisher : stranger);
    }

    /// @dev Half of the time, an exact boundary: the oldest day the window allows, the first day it refuses,
    ///      yesterday or today. Otherwise any day from 40 days back to 2 days ahead.
    function _day(uint256 seed) private view returns (uint32) {
        uint256 t = block.timestamp / 1 days;
        if (seed % 2 == 0) {
            uint256 k = (seed / 2) % 4;
            uint32 lag = anchor.maxLagDays(scope);
            if (k < 2 && lag != anchor.NO_LAG_LIMIT() && lag + 1 <= t) return uint32(t - lag - k);
            return uint32(t - (k % 2));
        }
        return uint32(bound(seed, t - 40, t + 2));
    }

    function _record(uint32 day) private {
        if (!touched[day]) {
            touched[day] = true;
            touchedDays.push(day);
        }
    }

    function _checkWindow(uint32 day) private {
        uint256 t = block.timestamp / 1 days;
        if (day >= t) openDayAnchored++;
        uint32 lag = anchor.maxLagDays(scope);
        if (lag != anchor.NO_LAG_LIMIT() && uint256(day) + lag < t) outsideWindowAnchored++;
    }

    function commitRoot(uint256 actorSeed, uint256 daySeed, bytes32 root) external {
        address a = _actor(actorSeed);
        uint32 day = _day(daySeed);
        address current = anchor.publisher(scope);
        vm.prank(a);
        try anchor.commitRoot(scope, day, root, "ipfs://d") {
            if (a != current) unauthorisedSuccesses++;
            _checkWindow(day);
            if (touched[day]) {
                rewrites++; // never update the model with a rewrite: it must not happen
            } else {
                _record(day);
                ghost[day] = Ghost(root, 0, false);
            }
        } catch {}
    }

    function markEmpty(uint256 actorSeed, uint256 daySeed) external {
        address a = _actor(actorSeed);
        uint32 day = _day(daySeed);
        address current = anchor.publisher(scope);
        vm.prank(a);
        try anchor.markEmpty(scope, day) {
            if (a != current) unauthorisedSuccesses++;
            _checkWindow(day);
            if (touched[day]) {
                rewrites++;
            } else {
                _record(day);
                ghost[day] = Ghost(bytes32(0), 0, true);
            }
        } catch {}
    }

    function correctRoot(uint256 actorSeed, uint256 daySeed, bytes32 newRoot, bool toEmpty, bytes32 reason) external {
        address a = _actor(actorSeed);
        uint32 day = _day(daySeed);
        if (toEmpty) newRoot = bytes32(0);
        vm.prank(a);
        try anchor.correctRoot(scope, day, newRoot, "ipfs://c", reason) {
            if (a != governor) unauthorisedSuccesses++;
            Ghost storage g = ghost[day];
            g.root = newRoot;
            g.empty = newRoot == bytes32(0);
            g.revision += 1;
        } catch {}
    }

    function setPublisher(uint256 actorSeed, uint32 lag, bool revoke, bool unlimited) external {
        address a = _actor(actorSeed);
        address p = revoke ? address(0) : publisher;
        uint32 l = revoke ? 0 : (unlimited ? anchor.NO_LAG_LIMIT() : uint32(bound(lag, 1, 60)));
        vm.prank(a);
        try anchor.setPublisher(scope, p, l) {
            if (a != governor) unauthorisedSuccesses++;
        } catch {}
    }

    function warp(uint256 secs) external {
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
        address governor = makeAddr("governor");
        address publisher = makeAddr("publisher");
        address stranger = makeAddr("stranger");
        reg = new VerifiablePolicyRegistry();
        vm.prank(governor);
        scope = reg.createScope("giga:XX:primary", 90 days);
        anchor = new MetricsAnchor(IPolicyRegistry(address(reg)));
        vm.prank(governor);
        anchor.setPublisher(scope, publisher, 7);
        handler = new AnchorHandler(reg, anchor, scope, governor, publisher, stranger);
        targetContract(address(handler));
    }

    /// Reachability: the handler reaches committed, empty and corrected days, publisher changes and time jumps,
    /// so the invariants are not vacuous. Actor seed 0 is the governor, 1 the publisher, 2 a stranger.
    function test_handlerReachesEveryState() public {
        uint256 t = block.timestamp / 1 days;
        handler.commitRoot(1, t - 1, keccak256("root"));
        handler.markEmpty(1, t - 2);
        handler.commitRoot(2, t - 3, keccak256("stranger")); // refused
        handler.correctRoot(0, t - 1, bytes32(0), true, keccak256("reason")); // root -> empty
        handler.correctRoot(0, t - 2, keccak256("late"), false, keccak256("reason")); // empty -> root
        assertEq(handler.dayCount(), 2);
        assertEq(handler.ghostOf(uint32(t - 1)).revision, 1);
        assertTrue(handler.ghostOf(uint32(t - 1)).empty);
        assertFalse(handler.ghostOf(uint32(t - 2)).empty);
        handler.setPublisher(0, 1, false, false);
        handler.commitRoot(1, t - 2 - 1, keccak256("old")); // outside a one-day window: refused
        assertEq(handler.dayCount(), 2);
        handler.warp(2 days);
        handler.commitRoot(1, t + 1, keccak256("after warp"));
        assertEq(handler.dayCount(), 3);
        assertEq(handler.unauthorisedSuccesses(), 0);
        invariant_daysMatchModel();
        invariant_committedDaysWellFormed();
        invariant_anchoringWindow();
        invariant_emptyDaysNeverVerify();
    }

    /// The stored state of every touched day equals the ghost model: the publisher writes a day once, and every
    /// later change is a governor correction that increments the revision.
    function invariant_daysMatchModel() public view {
        uint256 n = handler.dayCount();
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            MetricsAnchor.Commitment memory c = anchor.getCommitment(scope, day);
            AnchorHandler.Ghost memory g = handler.ghostOf(day);
            assertEq(c.root, g.root);
            assertEq(c.revision, g.revision);
            assertEq(c.empty, g.empty);
        }
    }

    /// A day is empty exactly when its root is zero, and it was committed only after it ended.
    function invariant_committedDaysWellFormed() public view {
        uint256 n = handler.dayCount();
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            MetricsAnchor.Commitment memory c = anchor.getCommitment(scope, day);
            assertGt(c.committedAt, 0);
            assertEq(c.empty, c.root == bytes32(0));
            assertGe(uint256(c.committedAt), (uint256(day) + 1) * 1 days);
        }
    }

    /// Only ended days, within the back-fill window in force, are ever anchored by the publisher, and never twice.
    function invariant_anchoringWindow() public view {
        assertEq(handler.openDayAnchored(), 0);
        assertEq(handler.outsideWindowAnchored(), 0);
        assertEq(handler.rewrites(), 0);
    }

    /// No row ever verifies against an empty day.
    function invariant_emptyDaysNeverVerify() public view {
        uint256 n = handler.dayCount();
        bytes32[] memory proof = new bytes32[](0);
        for (uint256 i = 0; i < n; i++) {
            uint32 day = handler.touchedDays(i);
            if (anchor.getCommitment(scope, day).empty) {
                assertFalse(anchor.verifyRow(scope, day, "giga-0001", "malware", 25, proof));
            }
        }
    }

    /// Only the publisher anchors, and only the governor corrects or appoints.
    function invariant_onlyAuthorisedWrites() public view {
        assertEq(handler.unauthorisedSuccesses(), 0);
    }
}
