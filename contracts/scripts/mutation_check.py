#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Targeted mutation check for the Foundry suites.

Each mutant injects one realistic bug into a contract and runs the Foundry suite that should catch it, with a
deliberately shallow campaign, under each of three fixed fuzzer seeds; the suite must fail under every seed.

- Mutants are applied to a temporary copy of contracts/, never to the working tree, so that a concurrent build,
  an editor or an interrupted run can never pick up a mutated source.
- A mutant that does not compile is reported as an error, not counted as killed.

The list mixes mutants written with the suites and mutants proposed by a separate internal review of the suites (marked "review").
It is a regression check, not a mutation score; the score over the whole test stack is measured separately with
slither-mutate (docs/security/CONTRACT_ASSURANCE.md §5).

Usage (from contracts/): python3 scripts/mutation_check.py
Exit code 0 if every mutant is killed under every seed, 1 otherwise.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEEDS = ["0x1", "0x2a", "0x7a69"]  # fixed, so that a result can be reproduced exactly
COPY = ["src", "test-foundry", "foundry.toml"]

REG = "src/VerifiablePolicyRegistry.sol"
ANC = "src/MetricsAnchor.sol"
RES = "src/IssuerRoleResolver.sol"

# (id, file, original text, mutated text, suite expected to fail, description)
MUTANTS = [
    ("A1", ANC, "if (day >= t) revert DayNotClosed();", "if (day > t) revert DayNotClosed();",
     "AnchorInvariants", "publisher may anchor the day that is still open"),
    ("A2", ANC, "uint256(day) + lag < t) revert DayTooOld();", "uint256(day) + lag + 1 < t) revert DayTooOld();",
     "AnchorInvariants", "back-fill window one day too wide"),
    ("A3", ANC, "if (msg.sender != _governor(scopeId)) revert NotGovernor();\n        Commitment storage c",
     "Commitment storage c", "AnchorInvariants", "anyone may correct a root"),
    ("A4", ANC, "if (_commitments[scopeId][day].committedAt != 0) revert DayAlreadyCommitted();", "",
     "AnchorInvariants", "publisher may rewrite an anchored day"),
    ("A5", ANC, "keccak256(abi.encodePacked(bytes1(0x01), computed, p))",
     "keccak256(abi.encodePacked(bytes1(0x00), computed, p))", "PropertyFuzz", "node tag confused with leaf tag"),
    ("A6", ANC, "if (c.committedAt == 0) revert DayNotCommitted();", "",
     "AnchorInvariants", "review: correction of a day never written"),
    ("A7", ANC, "if (newRoot == c.root) revert NoChange();", "",
     "AnchorInvariants", "review: no-op correction accepted"),
    ("A8", ANC, "bytes1(0x00), day, count, uint16(bytes(unitId).length)", "bytes1(0x01), day, count, uint16(bytes(unitId).length)",
     "PropertyFuzz", "review: leaf tag equal to node tag"),
    ("A9", ANC, "c.revision += 1;", "c.revision += 1;\n        c.committedAt = uint64(block.timestamp);",
     "AnchorInvariants", "review: a correction changes committedAt"),
    ("A10", ANC, "if ((newPublisher == address(0)) != (lagDays == 0)) revert InvalidLag();", "",
     "AnchorInvariants", "review: publisher appointed without a window"),
    ("A11", ANC, "if (reasonHash == bytes32(0)) revert EmptyReason();\n        if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();\n        bytes32 previous",
     "if (bytes(datasetUri).length > MAX_URI_LENGTH) revert UriTooLong();\n        bytes32 previous",
     "AnchorInvariants", "review: correction without a reason"),
    ("R1", REG, "validity > scopes[scopeId].maxValidity", "validity > MAX_VALIDITY_CAP",
     "RegistryInvariants", "validity bounded by the global cap instead of the scope's maximum"),
    ("R2", REG, "if ((reasonCode == REASON_APPEAL_ACCEPTED) != (resolvesAppeal != bytes32(0))) revert InvalidReasonCode();", "",
     "RegistryInvariants", "reason code 3 no longer tied to resolving an appeal"),
    ("R3", REG, "if (issuer == msg.sender || (role != Role.None && issuer == pendingGovernor[scopeId])) {",
     "if (issuer == msg.sender) {", "RegistryInvariants", "pending governor may be given an issuer role"),
    ("R4", REG, ") external onlyGovernor(scopeId) returns (uint256 version) {",
     ") external returns (uint256 version) {", "RegistryInvariants", "anyone may publish a policy version"),
    ("R5", REG, "if (a.status != AppealStatus.Open) revert AppealNotOpen();\n        if (msg.sender",
     "if (msg.sender", "RegistryInvariants", "a resolved appeal may be rejected again"),
    ("R6", REG, "if (a.scopeId != scopeId) revert AppealScopeMismatch();", "",
     "RegistryInvariants", "review: an appeal accepted by another scope's version"),
    ("R7", REG, "if (previous != AppealStatus.Rejected) revert AppealAlreadyExists();",
     "if (previous == AppealStatus.Open) revert AppealAlreadyExists();", "RegistryInvariants",
     "review: an accepted document may be filed again"),
    ("R8", REG, "if (maxValidity == 0 || maxValidity > MAX_VALIDITY_CAP) revert InvalidValidity();",
     "if (maxValidity == 0) revert InvalidValidity();", "RegistryInvariants", "review: scope validity above the cap"),
    ("R9", REG, "reasonCode > MAX_REASON_CODE) revert InvalidReasonCode();", "reasonCode >= MAX_REASON_CODE) revert InvalidReasonCode();",
     "RegistryInvariants", "review: highest valid reason code refused"),
    ("R10", REG, "if (bytes(uri).length > MAX_URI_LENGTH) revert UriTooLong();", "",
     "RegistryInvariants", "review: policy URI length not bounded"),
    ("R11", REG, "block.timestamp < policy.expiresAt", "block.timestamp <= policy.expiresAt",
     "RegistryInvariants", "review: a version still in force at its expiry instant"),
    ("R12", REG, "if (reasonHash == bytes32(0)) revert EmptyReason();\n        a.status = AppealStatus.Rejected;",
     "a.status = AppealStatus.Rejected;", "RegistryInvariants", "review: rejection without a reason"),
    ("E1", RES, "if (uint256(_word(data, offsetSlot)) != head) revert MalformedAttestation();", "",
     "PropertyFuzz", "non-canonical attestation encoding accepted"),
    ("E2", RES, "a.attester) == requiredRole;", "a.attester) >= requiredRole;",
     "PropertyFuzz", "review: a higher role accepted for a lower schema"),
    ("E3", RES, "if (!_check(list[i])) return false;", "",
     "PropertyFuzz", "review: batch accepted without checking its attestations"),
]


def forge(args, cwd, seed=None):
    env = dict(os.environ, FOUNDRY_FUZZ_RUNS="256", FOUNDRY_INVARIANT_RUNS="64", FOUNDRY_INVARIANT_DEPTH="32")
    if seed:
        env["FOUNDRY_FUZZ_SEED"] = seed
    return subprocess.run(["forge", *args], cwd=cwd, env=env, capture_output=True, text=True)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="vpr-mutants-") as tmp:
        work = pathlib.Path(tmp)
        for name in COPY:
            src = ROOT / name
            (shutil.copytree if src.is_dir() else shutil.copy2)(src, work / name)
        (work / "node_modules").symlink_to(ROOT / "node_modules")

        for seed in SEEDS:
            if forge(["test", "--match-contract", "Invariants|PropertyFuzz"], work, seed).returncode != 0:
                print(f"unmutated suites fail with seed {seed}; fix them before checking mutants")
                return 1

        survivors = errors = 0
        for mid, rel, original, mutated, suite, what in MUTANTS:
            path = work / rel
            source = path.read_text()
            if source.count(original) != 1:
                print(f"{mid:<4} ERROR     original text not found exactly once in {rel}")
                errors += 1
                continue
            path.write_text(source.replace(original, mutated))
            try:
                if forge(["build"], work).returncode != 0:
                    print(f"{mid:<4} ERROR     mutant does not compile")
                    errors += 1
                    continue
                survived = [s for s in SEEDS if forge(["test", "--match-contract", suite], work, s).returncode == 0]
            finally:
                path.write_text(source)
            survivors += bool(survived)
            status = "killed  " if not survived else "SURVIVED"
            print(f"{mid:<4} {status}  {len(SEEDS) - len(survived)}/{len(SEEDS)} seeds  {suite:<18} {what}")

    print(f"\n{len(MUTANTS) - survivors - errors}/{len(MUTANTS)} mutants killed under every seed")
    return 1 if survivors or errors else 0


if __name__ == "__main__":
    sys.exit(main())
