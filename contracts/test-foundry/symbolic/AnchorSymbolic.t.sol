// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../../src/VerifiablePolicyRegistry.sol";
import {MetricsAnchor, IPolicyRegistry} from "../../src/MetricsAnchor.sol";
import {SVM, SVM_ADDRESS} from "./SVM.sol";

/// @notice Symbolic checks of the metrics anchor with Halmos (docs/security/CONTRACT_ASSURANCE.md section 4.1).
///
/// Same method and limits as RegistrySymbolic: every `check_` function holds for all values of its parameters
/// within the command's bounds, from the concrete state of setUp, for one transaction. The anchoring window is
/// checked for every block.timestamp, so every UTC midnight and every window boundary is covered, not sampled.
///
/// Time is symbolic from the fixture time on (block.timestamp >= the setUp time). Checks with symbolic keys rely
/// on Halmos's model of keccak256 as injective, as in RegistrySymbolic.
/// Assumption: block.timestamp / 1 days fits in uint32, so `today()` does not truncate (until the year
/// 11 761 191).
///
/// The `check_leaf_*` functions are secondary: their conclusion is about keccak256 outputs, so it rests entirely
/// on Halmos's model of keccak256 as an injective function,
/// so they show that the leaf encoding is unambiguous and distinct from the node encoding as byte strings, not
/// anything about keccak256 itself.
contract AnchorSymbolic is Test {
    VerifiablePolicyRegistry internal reg;
    MetricsAnchor internal anchor;

    SVM internal constant svm = SVM(SVM_ADDRESS);

    address internal constant G1 = address(0x2001); // governor of S1
    address internal constant G2 = address(0x2002); // governor of S2
    address internal constant P1 = address(0x2003); // publisher of S1, window of 7 days
    address internal constant P2 = address(0x2004); // publisher of S2, no window limit

    bytes32 internal S1;
    bytes32 internal S2;
    bytes32 internal S3; // exists, no publisher

    uint32 internal constant LAG = 7;
    uint32 internal anchoredDay; // anchored by P1 in setUp
    uint32 internal emptyDay; // marked empty by P1 in setUp

    uint256 internal constant MAX_TS = uint256(type(uint32).max) * 1 days;

    /// Storage slot of `_commitments` (forge inspect MetricsAnchor storageLayout); setUp checks it against
    /// getCommitment. A Commitment is three words: root, datasetUri, (committedAt, revision, empty).
    uint256 internal constant COMMITMENTS_SLOT = 2;

    function setUp() public {
        vm.warp(20_000 days + 1 hours);
        reg = new VerifiablePolicyRegistry();
        anchor = new MetricsAnchor(IPolicyRegistry(address(reg)));

        vm.prank(G1);
        S1 = reg.createScope("giga:AR:primary", 30 days);
        vm.prank(G2);
        S2 = reg.createScope("giga:AR:secondary", 30 days);
        vm.prank(G2);
        S3 = reg.createScope("giga:AR:unpublished", 30 days);

        vm.prank(G1);
        anchor.setPublisher(S1, P1, LAG);
        vm.prank(G2);
        anchor.setPublisher(S2, P2, type(uint32).max); // NO_LAG_LIMIT (a getter call here would consume the prank)

        anchoredDay = anchor.today() - 1;
        emptyDay = anchor.today() - 2;
        vm.startPrank(P1);
        anchor.commitRoot(S1, anchoredDay, keccak256("release"), "ipfs://release");
        anchor.markEmpty(S1, emptyDay);
        vm.stopPrank();

        // The storage layout assumed by _words matches what getCommitment returns.
        (bytes32 root, uint64 committedAt, uint32 revision, bool empty) = _read(S1, anchoredDay);
        MetricsAnchor.Commitment memory c = anchor.getCommitment(S1, anchoredDay);
        require(root == c.root && committedAt == c.committedAt && revision == c.revision && empty == c.empty, "layout");
        (root, committedAt, revision, empty) = _read(S1, emptyDay);
        c = anchor.getCommitment(S1, emptyDay);
        require(root == c.root && committedAt == c.committedAt && revision == c.revision && empty == c.empty, "layout");
    }

    // ------------------------------------------------------------------ helpers

    /// Reads a commitment from raw storage. After a write to a symbolic slot, decoding the stored URI would need
    /// a symbolic memory offset, which Halmos does not support, so the checks read the fixed-size fields directly.
    function _read(bytes32 scopeId, uint32 day)
        internal
        view
        returns (bytes32 root, uint64 committedAt, uint32 revision, bool empty)
    {
        uint256 base = uint256(keccak256(abi.encode(uint256(day), keccak256(abi.encode(scopeId, COMMITMENTS_SLOT)))));
        root = vm.load(address(anchor), bytes32(base));
        uint256 packed = uint256(vm.load(address(anchor), bytes32(base + 2)));
        committedAt = uint64(packed);
        revision = uint32(packed >> 64);
        empty = uint8(packed >> 96) != 0;
    }

    /// INTERFACES I7: whether the publisher may write (scope, day) at time `ts`, from state read through getters.
    function _publishable(address caller, bytes32 scopeId, uint32 day, uint256 ts) internal view returns (bool) {
        address pub = anchor.publisher(scopeId);
        uint256 lag = anchor.maxLagDays(scopeId);
        uint256 t = ts / 1 days;
        (, uint64 committedAt,,) = _read(scopeId, day);
        return pub != address(0) && caller == pub && day < t
            && (lag == type(uint32).max || uint256(day) + lag >= t) && committedAt == 0;
    }

    // ------------------------------------------------------------------ acceptance rules

    /// commitRoot succeeds exactly when the caller is the scope's publisher, the UTC day has ended, the day is
    /// within the window (or the window is unbounded), the day was never written, the root is not zero and the
    /// URI is at most 256 bytes. On success the day holds the root, revision 0, not empty, committed now.
    function check_commitRoot_acceptedExactlyWhenSpecified(
        address caller,
        bytes32 scopeId,
        uint32 day,
        bytes32 root,
        string calldata datasetUri,
        uint256 ts
    ) public {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        bool spec = _publishable(caller, scopeId, day, ts) && root != bytes32(0) && bytes(datasetUri).length <= 256;

        vm.prank(caller);
        (bool ok,) = address(anchor).call(abi.encodeCall(anchor.commitRoot, (scopeId, day, root, datasetUri)));
        assert(ok == spec);
        if (!ok) return;

        (bytes32 r, uint64 committedAt, uint32 revision, bool empty) = _read(scopeId, day);
        assert(r == root && committedAt == ts && revision == 0 && !empty);
    }

    /// markEmpty succeeds under the same rules as commitRoot, without a root; on success the day is empty.
    function check_markEmpty_acceptedExactlyWhenSpecified(address caller, bytes32 scopeId, uint32 day, uint256 ts)
        public
    {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        bool spec = _publishable(caller, scopeId, day, ts);

        vm.prank(caller);
        (bool ok,) = address(anchor).call(abi.encodeCall(anchor.markEmpty, (scopeId, day)));
        assert(ok == spec);
        if (!ok) return;

        (bytes32 r, uint64 committedAt, uint32 revision, bool empty) = _read(scopeId, day);
        assert(r == bytes32(0) && committedAt == ts && revision == 0 && empty);
    }

    /// correctRoot succeeds exactly when the caller is the scope's current governor in the registry, the day was
    /// written, the new root differs from the current one, the reason hash is not zero and the URI is at most 256
    /// bytes. On success the root changes, the revision increases by one, the day is empty exactly when the new
    /// root is zero, and the original commit time is kept.
    function check_correctRoot_acceptedExactlyWhenSpecified(
        address caller,
        bytes32 scopeId,
        uint32 day,
        bytes32 newRoot,
        string calldata datasetUri,
        bytes32 reasonHash,
        uint256 ts
    ) public {
        _warpForward(ts); // at any later time, so that a correction that rewrote the commit time would show
        (bool spec, uint64 committedAt, uint32 revision) = _correctable(caller, scopeId, day, newRoot, reasonHash);
        spec = spec && bytes(datasetUri).length <= 256;

        vm.prank(caller);
        (bool ok,) =
            address(anchor).call(abi.encodeCall(anchor.correctRoot, (scopeId, day, newRoot, datasetUri, reasonHash)));
        assert(ok == spec);
        if (ok) _checkCorrected(scopeId, day, newRoot, committedAt, revision);
    }

    function _warpForward(uint256 ts) internal {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
    }

    function _checkCorrected(bytes32 scopeId, uint32 day, bytes32 newRoot, uint64 committedAt, uint32 revision)
        internal
        view
    {
        (bytes32 r, uint64 c, uint32 rev, bool empty) = _read(scopeId, day);
        assert(r == newRoot && c == committedAt && rev == revision + 1 && empty == (newRoot == bytes32(0)));
    }

    /// INTERFACES I7: whether a correction must succeed (apart from the URI bound), with the day's current
    /// commit time and revision.
    function _correctable(address caller, bytes32 scopeId, uint32 day, bytes32 newRoot, bytes32 reasonHash)
        internal
        view
        returns (bool spec, uint64 committedAt, uint32 revision)
    {
        (address governor,, bool exists) = reg.scopes(scopeId);
        bytes32 oldRoot;
        (oldRoot, committedAt, revision,) = _read(scopeId, day);
        spec = exists && caller == governor && committedAt != 0 && newRoot != oldRoot && reasonHash != bytes32(0);
    }

    /// setPublisher succeeds exactly when the caller is the scope's current governor and the window is 0 exactly
    /// for a revocation (publisher zero).
    function check_setPublisher_acceptedExactlyWhenSpecified(
        address caller,
        bytes32 scopeId,
        address newPublisher,
        uint32 lagDays
    ) public {
        (address governor,, bool exists) = reg.scopes(scopeId);
        bool spec = exists && caller == governor && ((newPublisher == address(0)) == (lagDays == 0));

        vm.prank(caller);
        (bool ok,) = address(anchor).call(abi.encodeCall(anchor.setPublisher, (scopeId, newPublisher, lagDays)));
        assert(ok == spec);
        if (!ok) return;

        assert(anchor.publisher(scopeId) == newPublisher && anchor.maxLagDays(scopeId) == lagDays);
    }

    // ------------------------------------------------------------------ frame condition

    /// One arbitrary call from an arbitrary sender at any later time: a written day keeps its commit time, its
    /// revision never decreases, and its root or emptiness changes only if the sender is the scope's governor.
    function check_anyCall_writtenDaysChangeOnlyByGovernor(address caller, uint256 ts) public {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        Day memory anchoredBefore = _day(S1, anchoredDay);
        Day memory emptyBefore = _day(S1, emptyDay);

        bytes memory data = svm.createCalldata("MetricsAnchor");
        vm.prank(caller);
        (bool ok,) = address(anchor).call(data);
        ok; // success or revert, the frame condition must hold

        _assertFrame(anchoredBefore, _day(S1, anchoredDay), caller == G1);
        _assertFrame(emptyBefore, _day(S1, emptyDay), caller == G1);
    }

    /// The fixed-size fields of one written day.
    struct Day {
        bytes32 root;
        uint64 committedAt;
        uint32 revision;
        bool empty;
    }

    function _day(bytes32 scopeId, uint32 day) internal view returns (Day memory d) {
        (d.root, d.committedAt, d.revision, d.empty) = _read(scopeId, day);
    }

    function _assertFrame(Day memory before, Day memory later, bool byGovernor) internal pure {
        assert(later.committedAt == before.committedAt && later.revision >= before.revision);
        assert((later.root == before.root && later.empty == before.empty) || byGovernor);
    }

    // ------------------------------------------------------------------ encoding (secondary, see contract note)

    /// Distinct rows have distinct leaves (bounded unit and category lengths; see scripts/symbolic_check.py).
    function check_leaf_distinctRowsHaveDistinctLeaves(
        uint32 dayA,
        string memory unitA,
        string memory categoryA,
        uint256 countA,
        uint32 dayB,
        string memory unitB,
        string memory categoryB,
        uint256 countB
    ) public view {
        bytes32 leafA = anchor.leafHash(dayA, unitA, categoryA, countA);
        bytes32 leafB = anchor.leafHash(dayB, unitB, categoryB, countB);
        bool same = dayA == dayB && countA == countB && _eq(bytes(unitA), bytes(unitB))
            && _eq(bytes(categoryA), bytes(categoryB));
        assert((leafA == leafB) == same);
    }

    /// Byte-wise equality, so that the predicate does not itself rely on keccak256.
    function _eq(bytes memory a, bytes memory b) internal pure returns (bool) {
        if (a.length != b.length) return false;
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    /// No leaf equals an internal node, so an internal node can never be presented as a row.
    function check_leaf_isNeverAnInternalNode(
        uint32 day,
        string calldata unitId,
        string calldata category,
        uint256 count,
        bytes32 left,
        bytes32 right
    ) public view {
        bytes32 node = keccak256(abi.encodePacked(bytes1(0x01), left, right));
        assert(anchor.leafHash(day, unitId, category, count) != node);
    }

    // ------------------------------------------------------------------ canary

    /// Must FAIL. The same check as commitRoot with the window boundary moved by one day in the predicate; a
    /// counterexample shows that Halmos reaches the boundary and that the checks above are not vacuous.
    function canary_commitRootWindowOffByOne(address caller, bytes32 scopeId, uint32 day, bytes32 root, uint256 ts)
        public
    {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        address pub = anchor.publisher(scopeId);
        uint256 lag = anchor.maxLagDays(scopeId);
        uint256 t = ts / 1 days;
        (, uint64 committedAt,,) = _read(scopeId, day);
        bool wrongSpec = pub != address(0) && caller == pub && day < t
            && (lag == type(uint32).max || uint256(day) + lag > t) && committedAt == 0 && root != bytes32(0);

        vm.prank(caller);
        (bool ok,) = address(anchor).call(abi.encodeCall(anchor.commitRoot, (scopeId, day, root, "")));
        assert(ok == wrongSpec);
    }
}
