#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Mutation check for the Foundry suites.

Each mutant injects a realistic bug into a contract (one textual change), runs the suite that should catch it with
a deliberately shallow campaign under each of three fixed fuzzer seeds, and requires the suite to fail under every
seed. A mutant that survives any seed means an invariant or fuzz test is weaker than claimed, or depends on luck.
The source file is always restored, also on error.

Usage (from contracts/): python3 scripts/mutation_check.py
Exit code 0 if every mutant is killed, 1 otherwise.
"""
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEEDS = ["0x1", "0x2a", "0x7a69"]  # fixed, so that a result can be reproduced exactly

# (id, file, original text, mutated text, suite expected to fail, description)
MUTANTS = [
    ("A1", "src/MetricsAnchor.sol", "if (day >= t) revert DayNotClosed();", "if (day > t) revert DayNotClosed();",
     "AnchorInvariants", "publisher may anchor the day that is still open"),
    ("A2", "src/MetricsAnchor.sol", "uint256(day) + lag < t) revert DayTooOld();", "uint256(day) + lag + 1 < t) revert DayTooOld();",
     "AnchorInvariants", "back-fill window one day too wide"),
    ("A3", "src/MetricsAnchor.sol", "if (msg.sender != _governor(scopeId)) revert NotGovernor();\n        Commitment storage c",
     "Commitment storage c", "AnchorInvariants", "anyone may correct a root"),
    ("A4", "src/MetricsAnchor.sol", "if (_commitments[scopeId][day].committedAt != 0) revert DayAlreadyCommitted();", "",
     "AnchorInvariants", "publisher may rewrite an anchored day"),
    ("A5", "src/MetricsAnchor.sol", "keccak256(abi.encodePacked(bytes1(0x01), computed, p))",
     "keccak256(abi.encodePacked(bytes1(0x00), computed, p))", "PropertyFuzz", "node tag confused with leaf tag"),
    ("R1", "src/VerifiablePolicyRegistry.sol", "validity > scopes[scopeId].maxValidity", "validity > MAX_VALIDITY_CAP",
     "RegistryInvariants", "validity bounded by the global cap instead of the scope's maximum"),
    ("R2", "src/VerifiablePolicyRegistry.sol",
     "if ((reasonCode == REASON_APPEAL_ACCEPTED) != (resolvesAppeal != bytes32(0))) revert InvalidReasonCode();", "",
     "RegistryInvariants", "reason code 3 no longer tied to resolving an appeal"),
    ("R3", "src/VerifiablePolicyRegistry.sol",
     "if (issuer == msg.sender || (role != Role.None && issuer == pendingGovernor[scopeId])) {",
     "if (issuer == msg.sender) {", "RegistryInvariants", "pending governor may be given an issuer role"),
    ("R4", "src/VerifiablePolicyRegistry.sol", ") external onlyGovernor(scopeId) returns (uint256 version) {",
     ") external returns (uint256 version) {", "RegistryInvariants", "anyone may publish a policy version"),
    ("R5", "src/VerifiablePolicyRegistry.sol", "if (a.status != AppealStatus.Open) revert AppealNotOpen();\n        if (msg.sender",
     "if (msg.sender", "RegistryInvariants", "a resolved appeal may be rejected again"),
    ("E1", "src/IssuerRoleResolver.sol", "if (uint256(_word(data, offsetSlot)) != head) revert MalformedAttestation();", "",
     "PropertyFuzz", "non-canonical attestation encoding accepted"),
]


def run_suite(suite: str, seed: str) -> bool:
    env = dict(os.environ, FOUNDRY_FUZZ_RUNS="256", FOUNDRY_INVARIANT_RUNS="64", FOUNDRY_INVARIANT_DEPTH="32",
               FOUNDRY_FUZZ_SEED=seed)
    r = subprocess.run(["forge", "test", "--match-contract", suite], cwd=ROOT, env=env, capture_output=True, text=True)
    return r.returncode == 0


def main() -> int:
    for seed in SEEDS:
        if not run_suite("Invariants|PropertyFuzz", seed):
            print(f"unmutated suite fails with seed {seed}; fix it before checking mutants")
            return 1
    survivors = 0
    for mid, rel, original, mutated, suite, what in MUTANTS:
        path = ROOT / rel
        source = path.read_text()
        if source.count(original) != 1:
            print(f"{mid}  ERROR  original text not found exactly once in {rel}")
            return 1
        try:
            path.write_text(source.replace(original, mutated))
            survived_seeds = [seed for seed in SEEDS if run_suite(suite, seed)]
        finally:
            path.write_text(source)
        killed = len(SEEDS) - len(survived_seeds)
        status = "killed  " if not survived_seeds else "SURVIVED"
        survivors += bool(survived_seeds)
        print(f"{mid}  {status}  {killed}/{len(SEEDS)} seeds  {suite:<18} {what}")
    print(f"\n{len(MUTANTS) - survivors}/{len(MUTANTS)} mutants killed")
    return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
