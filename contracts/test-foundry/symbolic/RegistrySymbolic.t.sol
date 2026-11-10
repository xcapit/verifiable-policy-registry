// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {VerifiablePolicyRegistry} from "../../src/VerifiablePolicyRegistry.sol";
import {SVM, SVM_ADDRESS} from "./SVM.sol";

/// @notice Symbolic checks of the registry with Halmos (docs/security/CONTRACT_ASSURANCE.md section 4.1).
///
/// Every `check_` function is explored for ALL values of its parameters, within the bounds set by the Halmos
/// command (string lengths {0, 256, 257}; see scripts/symbolic_check.py). Each one starts from the concrete state
/// built in setUp and covers exactly one transaction, so these are bounded, single-step results: they are not an
/// induction over all reachable states. The fuzzing campaigns in RegistryInvariants cover sequences.
///
/// Two kinds of check:
///  - Acceptance rules. A function is called with a low-level call and `ok` is compared with a predicate written
///    from docs/INTERFACES.md I2. The predicate reads state through public getters and never calls the contract's
///    own checks. A plain call would not do: Halmos treats a reverting path as passing, so a contract that
///    wrongly refused a valid call would go unnoticed.
///  - Frame conditions. One call with arbitrary calldata (any function, any arguments) from an arbitrary sender,
///    after which state that the specification says is final must be unchanged.
///
/// Keccak256. Mapping slots are keccak256 of the key, and Halmos models keccak256 as injective; every check with
/// a symbolic key (scope, appeal or address) relies on that model to keep distinct keys in distinct slots.
///
/// Time is symbolic from the fixture time on (block.timestamp >= the setUp time).
/// Assumption: block.timestamp + MAX_VALIDITY_CAP < 2^64, so `uint64(block.timestamp)` does not truncate and
/// `publishedAt + validity` does not overflow (the bound is reached in about 5.8 * 10^11 years).
contract RegistrySymbolic is Test {
    VerifiablePolicyRegistry internal reg;

    SVM internal constant svm = SVM(SVM_ADDRESS);

    address internal constant G1 = address(0x1001); // governor of S1
    address internal constant G2 = address(0x1002); // governor of S2
    address internal constant PENDING = address(0x1003); // proposed governor of S1
    address internal constant OPERATOR = address(0x1004); // holds a role in S1

    bytes32 internal S1; // maxValidity 30 days
    bytes32 internal S2; // maxValidity 365 days

    bytes32 internal constant DOC_OPEN = keccak256("doc-open");
    bytes32 internal constant DOC_REJECTED = keccak256("doc-rejected");
    bytes32 internal constant DOC_ACCEPTED = keccak256("doc-accepted");
    bytes32 internal constant DOC_OTHER_SCOPE = keccak256("doc-other-scope");

    bytes32 internal openAppeal; // open, in S1
    bytes32 internal rejectedAppeal; // rejected, in S1
    bytes32 internal acceptedAppeal; // accepted by version 2 of S1
    bytes32 internal otherScopeAppeal; // open, in S2

    uint256 internal constant MAX_TS = type(uint64).max - 365 days;

    VerifiablePolicyRegistry.AppealStatus internal constant OPEN = VerifiablePolicyRegistry.AppealStatus.Open;
    VerifiablePolicyRegistry.AppealStatus internal constant ACCEPTED = VerifiablePolicyRegistry.AppealStatus.Accepted;
    VerifiablePolicyRegistry.AppealStatus internal constant REJECTED = VerifiablePolicyRegistry.AppealStatus.Rejected;

    function setUp() public {
        vm.warp(1_800_000_000);
        reg = new VerifiablePolicyRegistry();

        vm.prank(G1);
        S1 = reg.createScope("giga:AR:primary", 30 days);
        vm.prank(G2);
        S2 = reg.createScope("giga:AR:secondary", 365 days);

        vm.startPrank(G1);
        reg.publishPolicy(S1, keccak256("v1"), bytes32(0), "ipfs://v1", 1, 30 days, bytes32(0));
        reg.setIssuer(S1, OPERATOR, VerifiablePolicyRegistry.Role.Operator);
        reg.proposeGovernor(S1, PENDING);
        vm.stopPrank();

        openAppeal = reg.fileAppeal(S1, DOC_OPEN);
        rejectedAppeal = reg.fileAppeal(S1, DOC_REJECTED);
        acceptedAppeal = reg.fileAppeal(S1, DOC_ACCEPTED);
        otherScopeAppeal = reg.fileAppeal(S2, DOC_OTHER_SCOPE);

        vm.startPrank(G1);
        reg.rejectAppeal(rejectedAppeal, keccak256("reasoned decision"));
        reg.publishPolicy(S1, keccak256("v2"), bytes32(0), "ipfs://v2", 3, 7 days, acceptedAppeal);
        vm.stopPrank();

        // The storage layout assumed by _versionWords matches what getVersion returns.
        for (uint256 v = 1; v <= 2; v++) {
            bytes32[5] memory w = _versionWords(S1, v);
            VerifiablePolicyRegistry.PolicyVersion memory p = reg.getVersion(S1, v);
            require(w[0] == p.contentHash && w[4] == p.resolvesAppeal, "storage layout");
            require(uint256(w[2]) == (uint256(bytes32(bytes(p.uri))) | (bytes(p.uri).length * 2)), "short string");
        }
    }

    // ------------------------------------------------------------------ helpers reading state through getters

    function _scope(bytes32 id) internal view returns (address governor, uint64 maxValidity, bool exists) {
        return reg.scopes(id);
    }

    function _appeal(bytes32 id)
        internal
        view
        returns (bytes32 scopeId, VerifiablePolicyRegistry.AppealStatus status, bytes32 resolution)
    {
        (scopeId, status,,,, resolution) = reg.appeals(id);
    }

    /// Storage slot of `_versions` in the registry (forge inspect VerifiablePolicyRegistry storageLayout); setUp
    /// checks it against getVersion, so a layout change makes the checks fail instead of passing vacuously.
    uint256 internal constant VERSIONS_SLOT = 3;
    /// Storage words of one PolicyVersion: contentHash, restrictedListHash, uri, (reasonCode, publishedAt,
    /// expiresAt), resolvesAppeal.
    uint256 internal constant VERSION_WORDS = 5;

    /// The raw storage words of version `v` (1-based) of a scope. The frame checks compare words rather than
    /// getVersion results: after a write to a symbolic slot, decoding the stored string would need a symbolic
    /// memory offset, which Halmos does not support. The URIs written in setUp are shorter than 32 bytes, so
    /// their whole content is in the uri word.
    function _versionWords(bytes32 scopeId, uint256 v) internal view returns (bytes32[5] memory w) {
        uint256 data = uint256(keccak256(abi.encode(keccak256(abi.encode(scopeId, VERSIONS_SLOT)))));
        for (uint256 i = 0; i < VERSION_WORDS; i++) {
            w[i] = vm.load(address(reg), bytes32(data + (v - 1) * VERSION_WORDS + i));
        }
    }

    // ------------------------------------------------------------------ acceptance rules

    /// Arguments of one publishPolicy call (a struct, to stay within the stack limit).
    struct Publish {
        address caller;
        bytes32 scopeId;
        bytes32 contentHash;
        bytes32 restrictedListHash;
        string uri;
        uint16 reasonCode;
        uint64 validity;
        bytes32 resolvesAppeal;
    }

    /// INTERFACES I2: the conditions under which publishPolicy must succeed, read from state through getters.
    function _publishAccepted(Publish memory p) internal view returns (bool) {
        (address governor, uint64 maxValidity, bool exists) = _scope(p.scopeId);
        (bytes32 appealScope, VerifiablePolicyRegistry.AppealStatus appealStatus,) = _appeal(p.resolvesAppeal);
        return exists && p.caller == governor && p.contentHash != bytes32(0) && p.validity != 0
            && p.validity <= maxValidity && bytes(p.uri).length <= 256 && p.reasonCode >= 1 && p.reasonCode <= 6
            && ((p.reasonCode == 3) == (p.resolvesAppeal != bytes32(0)))
            && (p.resolvesAppeal == bytes32(0) || (appealStatus == OPEN && appealScope == p.scopeId));
    }

    /// publishPolicy succeeds exactly when INTERFACES I2 accepts it, and on success appends exactly the version
    /// described by its arguments, in force from now, and, if it resolves an appeal, accepts that appeal and no
    /// other.
    function check_publishPolicy_acceptedExactlyWhenSpecified(
        address caller,
        bytes32 scopeId,
        bytes32 contentHash,
        bytes32 restrictedListHash,
        string calldata uri,
        uint16 reasonCode,
        uint64 validity,
        bytes32 resolvesAppeal,
        uint256 ts
    ) public {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        Publish memory p =
            Publish(caller, scopeId, contentHash, restrictedListHash, uri, reasonCode, validity, resolvesAppeal);
        bool spec = _publishAccepted(p);
        uint256 before = reg.versionCount(scopeId);

        vm.prank(caller);
        (bool ok,) = address(reg).call(
            abi.encodeCall(
                reg.publishPolicy,
                (p.scopeId, p.contentHash, p.restrictedListHash, p.uri, p.reasonCode, p.validity, p.resolvesAppeal)
            )
        );
        assert(ok == spec);
        if (ok) _checkPublished(p, before, ts);
    }

    function _checkPublished(Publish memory p, uint256 before, uint256 ts) internal view {
        assert(reg.versionCount(p.scopeId) == before + 1);
        VerifiablePolicyRegistry.PolicyVersion memory v = reg.getVersion(p.scopeId, before + 1);
        assert(v.contentHash == p.contentHash);
        assert(v.restrictedListHash == p.restrictedListHash);
        assert(keccak256(bytes(v.uri)) == keccak256(bytes(p.uri)));
        assert(v.reasonCode == p.reasonCode);
        assert(v.publishedAt == ts);
        assert(v.expiresAt == ts + p.validity);
        assert(v.resolvesAppeal == p.resolvesAppeal);

        (uint256 current,, bool inForce) = reg.currentPolicy(p.scopeId);
        assert(current == before + 1 && inForce);

        if (p.resolvesAppeal != bytes32(0)) {
            (bytes32 s, VerifiablePolicyRegistry.AppealStatus st, bytes32 resolution) = _appeal(p.resolvesAppeal);
            assert(s == p.scopeId && st == ACCEPTED && resolution == p.contentHash);
        }
        // The open appeals fixed in setUp that this call does not resolve stay open.
        if (p.resolvesAppeal != openAppeal) {
            (, VerifiablePolicyRegistry.AppealStatus st,) = _appeal(openAppeal);
            assert(st == OPEN);
        }
        if (p.resolvesAppeal != otherScopeAppeal) {
            (, VerifiablePolicyRegistry.AppealStatus st,) = _appeal(otherScopeAppeal);
            assert(st == OPEN);
        }
    }

    /// rejectAppeal succeeds exactly when the appeal is open, the caller governs the appeal's scope and the reason
    /// hash is not zero; on success the appeal is rejected with that reason and keeps its scope.
    function check_rejectAppeal_acceptedExactlyWhenSpecified(address caller, bytes32 appealId, bytes32 reasonHash)
        public
    {
        (bytes32 scopeId, VerifiablePolicyRegistry.AppealStatus status,) = _appeal(appealId);
        (address governor,,) = _scope(scopeId);

        bool spec = status == OPEN && caller == governor && reasonHash != bytes32(0);

        vm.prank(caller);
        (bool ok,) = address(reg).call(abi.encodeCall(reg.rejectAppeal, (appealId, reasonHash)));
        assert(ok == spec);
        if (!ok) return;

        (bytes32 s, VerifiablePolicyRegistry.AppealStatus st, bytes32 resolution) = _appeal(appealId);
        assert(s == scopeId && st == REJECTED && resolution == reasonHash);
    }

    /// fileAppeal succeeds exactly when the scope exists, the document hash is not zero and the document has no
    /// round yet or its latest round was rejected; on success it opens round + 1 in that scope.
    function check_fileAppeal_acceptedExactlyWhenSpecified(address caller, bytes32 scopeId, bytes32 documentHash)
        public
    {
        (,, bool exists) = _scope(scopeId);
        uint32 round = reg.appealRounds(keccak256(abi.encode(scopeId, documentHash)));
        (, VerifiablePolicyRegistry.AppealStatus latest,) = _appeal(reg.appealIdOf(scopeId, documentHash, round));

        bool spec = exists && documentHash != bytes32(0) && (round == 0 || latest == REJECTED);

        vm.prank(caller);
        (bool ok, bytes memory ret) = address(reg).call(abi.encodeCall(reg.fileAppeal, (scopeId, documentHash)));
        assert(ok == spec);
        if (!ok) return;

        bytes32 id = abi.decode(ret, (bytes32));
        assert(id == reg.appealIdOf(scopeId, documentHash, round + 1));
        (bytes32 s, VerifiablePolicyRegistry.AppealStatus st, bytes32 resolution) = _appeal(id);
        assert(s == scopeId && st == OPEN && resolution == bytes32(0));
        assert(reg.appealRounds(keccak256(abi.encode(scopeId, documentHash))) == round + 1);
    }

    /// setIssuer succeeds exactly when the caller governs the scope, the issuer is not zero, the issuer is not the
    /// governor, and a non-None role is not given to the pending governor.
    function check_setIssuer_acceptedExactlyWhenSpecified(address caller, bytes32 scopeId, address issuer, uint8 role)
        public
    {
        vm.assume(role <= uint8(VerifiablePolicyRegistry.Role.Auditor));
        (address governor,, bool exists) = _scope(scopeId);
        address pending = reg.pendingGovernor(scopeId);

        bool spec = exists && caller == governor && issuer != address(0) && issuer != governor
            && (role == 0 || issuer != pending);

        vm.prank(caller);
        (bool ok,) = address(reg).call(
            abi.encodeCall(reg.setIssuer, (scopeId, issuer, VerifiablePolicyRegistry.Role(role)))
        );
        assert(ok == spec);
        if (ok) assert(uint8(reg.issuerRole(scopeId, issuer)) == role);
    }

    /// createScope succeeds exactly when the name is 1 to 128 bytes, 0 < maxValidity <= 365 days and the caller
    /// has not created a scope with that name; on success the caller governs the new scope.
    function check_createScope_acceptedExactlyWhenSpecified(address caller, string calldata name, uint64 maxValidity)
        public
    {
        bytes32 id = reg.scopeIdOf(caller, name);
        (,, bool exists) = _scope(id);
        bool spec = bytes(name).length >= 1 && bytes(name).length <= 128 && maxValidity >= 1
            && maxValidity <= 365 days && !exists;

        vm.prank(caller);
        (bool ok, bytes memory ret) = address(reg).call(abi.encodeCall(reg.createScope, (name, maxValidity)));
        assert(ok == spec);
        if (!ok) return;

        assert(abi.decode(ret, (bytes32)) == id);
        (address governor, uint64 v, bool e) = _scope(id);
        assert(governor == caller && v == maxValidity && e);
        assert(reg.versionCount(id) == 0);
    }

    /// proposeGovernor succeeds exactly when the caller governs the scope and the proposed address holds no role
    /// in it; acceptGovernor succeeds exactly when a handover is pending and the caller is the proposed governor,
    /// who then governs the scope with no handover pending.
    function check_handover_acceptedExactlyWhenSpecified(address caller, bytes32 scopeId, address proposed) public {
        (address governor,, bool exists) = _scope(scopeId);
        bool spec = exists && caller == governor && reg.issuerRole(scopeId, proposed) == VerifiablePolicyRegistry.Role.None;
        vm.prank(caller);
        (bool ok,) = address(reg).call(abi.encodeCall(reg.proposeGovernor, (scopeId, proposed)));
        assert(ok == spec);
        if (ok) assert(reg.pendingGovernor(scopeId) == proposed);

        address pending = reg.pendingGovernor(scopeId);
        spec = exists && pending != address(0) && proposed == pending;
        vm.prank(proposed);
        (ok,) = address(reg).call(abi.encodeCall(reg.acceptGovernor, (scopeId)));
        assert(ok == spec);
        if (!ok) return;
        (address newGovernor,,) = _scope(scopeId);
        assert(newGovernor == pending && reg.pendingGovernor(scopeId) == address(0));
    }

    /// For every later time, currentPolicy returns the latest version and reports it in force exactly while
    /// block.timestamp < expiresAt.
    function check_currentPolicy_inForceExactlyBeforeExpiry(uint256 ts) public {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);
        (uint256 version, VerifiablePolicyRegistry.PolicyVersion memory p, bool inForce) = reg.currentPolicy(S1);
        assert(version == 2 && p.contentHash == keccak256("v2"));
        assert(inForce == (ts < p.expiresAt));
    }

    // ------------------------------------------------------------------ frame conditions

    /// One arbitrary call from an arbitrary sender: neither stored version of S1 changes, a resolved appeal keeps
    /// its status and resolution, and an open appeal never returns to None.
    function check_anyCall_keepsVersionsAndResolvedAppeals(address caller, uint256 ts) public {
        vm.assume(ts >= block.timestamp && ts <= MAX_TS);
        vm.warp(ts);

        bytes32[5] memory v1 = _versionWords(S1, 1);
        bytes32[5] memory v2 = _versionWords(S1, 2);
        (, , bytes32 rejectedResolution) = _appeal(rejectedAppeal);
        (, , bytes32 acceptedResolution) = _appeal(acceptedAppeal);

        bytes memory data = svm.createCalldata("VerifiablePolicyRegistry");
        vm.prank(caller);
        (bool ok,) = address(reg).call(data);
        ok; // success or revert, the frame conditions must hold

        assert(reg.versionCount(S1) >= 2);
        bytes32[5] memory w1 = _versionWords(S1, 1);
        bytes32[5] memory w2 = _versionWords(S1, 2);
        for (uint256 i = 0; i < VERSION_WORDS; i++) {
            assert(w1[i] == v1[i] && w2[i] == v2[i]);
        }

        (bytes32 s, VerifiablePolicyRegistry.AppealStatus st, bytes32 r) = _appeal(rejectedAppeal);
        assert(s == S1 && st == REJECTED && r == rejectedResolution);
        (s, st, r) = _appeal(acceptedAppeal);
        assert(s == S1 && st == ACCEPTED && r == acceptedResolution);
        (s, st,) = _appeal(openAppeal);
        assert(s == S1 && st != VerifiablePolicyRegistry.AppealStatus.None);
    }

    /// One arbitrary call from an arbitrary sender: afterwards, neither the governor nor the pending governor of
    /// S1 holds an issuer role, whichever function was called (including proposeGovernor, acceptGovernor and
    /// setIssuer with arbitrary arguments).
    function check_anyCall_governorHoldsNoRole(address caller) public {
        bytes memory data = svm.createCalldata("VerifiablePolicyRegistry");
        vm.prank(caller);
        (bool ok,) = address(reg).call(data);
        ok;

        (address governor,,) = _scope(S1);
        address pending = reg.pendingGovernor(S1);
        assert(reg.issuerRole(S1, governor) == VerifiablePolicyRegistry.Role.None);
        assert(reg.issuerRole(S1, pending) == VerifiablePolicyRegistry.Role.None);
    }

    // ------------------------------------------------------------------ canary

    /// Must FAIL. The publishPolicy check with the validity bound tightened by one second in the predicate; a
    /// counterexample shows that Halmos reaches validity == maxValidity and that the checks are not vacuous.
    function canary_publishValidityOffByOne(address caller, bytes32 scopeId, uint64 validity) public {
        (address governor, uint64 maxValidity, bool exists) = _scope(scopeId);
        bool wrongSpec = exists && caller == governor && validity != 0 && validity < maxValidity;
        vm.prank(caller);
        (bool ok,) = address(reg).call(
            abi.encodeCall(reg.publishPolicy, (scopeId, keccak256("c"), bytes32(0), "", 1, validity, bytes32(0)))
        );
        assert(ok == wrongSpec);
    }
}
