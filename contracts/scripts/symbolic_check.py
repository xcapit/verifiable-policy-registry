#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Symbolic checks of the contracts with Halmos (docs/security/CONTRACT_ASSURANCE.md section 4.1).

Runs every check in test-foundry/symbolic/ and accepts the result only if:

- every expected `check_` function is present and PASSES, with no solver timeout, no error and no path cut by a
  loop bound (Halmos reports such paths in `num_bounded_loops`; a cut path is an unexplored path, not a pass);
- every `canary_` function FAILS with a counterexample. A canary is a check with a deliberately wrong predicate;
  it shows that the boundary it moves is reached, so that a pass elsewhere is not vacuous.

With --mutants, it also injects bugs from scripts/mutation_check.py into a temporary copy of contracts/ and
requires the named check to fail on each one.

Bounds. Strings and bytes have lengths {0, 256, 257} unless set below; loops are unrolled up to 16 times; the
solver runs without timeouts, so every branch is decided exactly. Results hold within these bounds, for one
transaction from the concrete state built in each suite's setUp.

Usage (from contracts/): python3 scripts/symbolic_check.py [--mutants]
Environment: HALMOS, the Halmos executable (default: halmos). Tested with Halmos 0.3.3 and the Yices 2.6.4 SMT
solver (pip packages halmos==0.3.3 and yices-solver==2.6.4.post23), on Python 3.12.
Exit code 0 if every condition holds, 1 otherwise.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HALMOS = os.environ.get("HALMOS", "halmos")

COMMON = [
    "--forge-build-out", "out-forge",
    "--default-bytes-lengths", "0,256,257",
    "--array-lengths",
    # scope names around the 128-byte bound; rows short enough to keep the leaf checks tractable, with one
    # length (24) at which a leaf preimage has the length of a node preimage (1 + 4 + 32 + 2 + 2 + 24 = 65)
    "name={0,1,128,129},unitA={0,1,2},categoryA={0,1,2},unitB={0,1,2},categoryB={0,1,2},unitId={0,24},category={0,24}",
    "--loop", "16",
    "--solver-timeout-branching", "0",
    "--solver-timeout-assertion", "0",
    "--no-status",
]

EXPECTED = {
    "RegistrySymbolic": [
        "check_publishPolicy_acceptedExactlyWhenSpecified",
        "check_rejectAppeal_acceptedExactlyWhenSpecified",
        "check_fileAppeal_acceptedExactlyWhenSpecified",
        "check_setIssuer_acceptedExactlyWhenSpecified",
        "check_createScope_acceptedExactlyWhenSpecified",
        "check_handover_acceptedExactlyWhenSpecified",
        "check_currentPolicy_inForceExactlyBeforeExpiry",
        "check_anyCall_keepsVersionsAndResolvedAppeals",
        "check_anyCall_governorHoldsNoRole",
        "canary_publishValidityOffByOne",
    ],
    "AnchorSymbolic": [
        "check_commitRoot_acceptedExactlyWhenSpecified",
        "check_markEmpty_acceptedExactlyWhenSpecified",
        "check_correctRoot_acceptedExactlyWhenSpecified",
        "check_setPublisher_acceptedExactlyWhenSpecified",
        "check_anyCall_writtenDaysChangeOnlyByGovernor",
        "check_leaf_distinctRowsHaveDistinctLeaves",
        "check_leaf_isNeverAnInternalNode",
        "canary_commitRootWindowOffByOne",
    ],
}

# Mutant id (scripts/mutation_check.py) -> (suite, check that must fail). Mutants of verifyRow's node hashing
# (A5) and of the resolver (E*) are outside these suites and stay with the fuzz tests.
MUTANT_CHECKS = {
    "A1": ("AnchorSymbolic", "check_commitRoot_acceptedExactlyWhenSpecified"),
    "A2": ("AnchorSymbolic", "check_commitRoot_acceptedExactlyWhenSpecified"),
    "A3": ("AnchorSymbolic", "check_correctRoot_acceptedExactlyWhenSpecified"),
    "A4": ("AnchorSymbolic", "check_commitRoot_acceptedExactlyWhenSpecified"),
    "A6": ("AnchorSymbolic", "check_correctRoot_acceptedExactlyWhenSpecified"),
    "A7": ("AnchorSymbolic", "check_correctRoot_acceptedExactlyWhenSpecified"),
    "A8": ("AnchorSymbolic", "check_leaf_isNeverAnInternalNode"),
    "A9": ("AnchorSymbolic", "check_correctRoot_acceptedExactlyWhenSpecified"),
    "A10": ("AnchorSymbolic", "check_setPublisher_acceptedExactlyWhenSpecified"),
    "A11": ("AnchorSymbolic", "check_correctRoot_acceptedExactlyWhenSpecified"),
    "R1": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R2": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R3": ("RegistrySymbolic", "check_setIssuer_acceptedExactlyWhenSpecified"),
    "R4": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R5": ("RegistrySymbolic", "check_rejectAppeal_acceptedExactlyWhenSpecified"),
    "R6": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R7": ("RegistrySymbolic", "check_fileAppeal_acceptedExactlyWhenSpecified"),
    "R8": ("RegistrySymbolic", "check_createScope_acceptedExactlyWhenSpecified"),
    "R9": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R10": ("RegistrySymbolic", "check_publishPolicy_acceptedExactlyWhenSpecified"),
    "R11": ("RegistrySymbolic", "check_currentPolicy_inForceExactlyBeforeExpiry"),
    "R12": ("RegistrySymbolic", "check_rejectAppeal_acceptedExactlyWhenSpecified"),
}


def halmos(root: pathlib.Path, suite: str, match: str, out: pathlib.Path) -> dict:
    """Run one Halmos invocation and return {test name without signature: result record}."""
    cmd = [HALMOS, "--root", str(root), "--contract", suite, "--match-test", match, "--json-output", str(out), *COMMON]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if not out.exists():
        print(proc.stdout[-4000:], proc.stderr[-4000:], sep="\n")
        raise SystemExit(f"halmos produced no result for {suite} (exit code {proc.returncode})")
    results = {}
    for tests in json.loads(out.read_text())["test_results"].values():
        for t in tests:
            results[t["name"].split("(")[0]] = t
    return results


def verdict(t: dict) -> str:
    """PASS, FAIL (counterexample found), or the reason the result cannot be accepted."""
    if t["exitcode"] == 0 and t["num_bounded_loops"] == 0:
        return "PASS"
    if t["exitcode"] == 0:
        return "INCOMPLETE (a loop bound cut some paths)"
    if t["exitcode"] == 1 and t["num_models"] > 0:
        return "FAIL"
    return {2: "TIMEOUT", 3: "STUCK", 4: "ALL PATHS REVERT"}.get(t["exitcode"], f"ERROR (exit code {t['exitcode']})")


def check_suites(tmp: pathlib.Path) -> bool:
    good = True
    for suite, names in EXPECTED.items():
        results = halmos(ROOT, suite, "^(check_|canary_)", tmp / f"{suite}.json")
        for name in names:
            t = results.get(name)
            got = verdict(t) if t else "MISSING"
            want = "FAIL" if name.startswith("canary_") else "PASS"
            ok = got == want
            good &= ok
            paths = t["num_paths"][0] if t else 0
            print(f"{'ok ' if ok else 'BAD'} {suite}.{name}: {got} (paths: {paths}, expected {want})")
        for extra in sorted(set(results) - set(names)):
            print(f"BAD {suite}.{extra}: not in the expected list of scripts/symbolic_check.py")
            good = False
    return good


def check_mutants(tmp: pathlib.Path) -> bool:
    sys.path.insert(0, str(ROOT / "scripts"))
    from mutation_check import MUTANTS  # the same mutants as the fuzz suites, applied the same way

    work = tmp / "work"
    for name in ["src", "test-foundry", "foundry.toml"]:
        src = ROOT / name
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, work / name)
    (work / "node_modules").symlink_to(ROOT / "node_modules")

    good = True
    for mid, rel, original, mutated, _suite, what in MUTANTS:
        if mid not in MUTANT_CHECKS:
            continue
        suite, check = MUTANT_CHECKS[mid]
        path = work / rel
        source = path.read_text()
        if source.count(original) != 1:
            print(f"BAD {mid}: original text not found exactly once in {rel}")
            good = False
            continue
        path.write_text(source.replace(original, mutated))
        try:
            got = halmos(work, suite, f"^{check}\\(", tmp / f"{mid}.json").get(check)
            caught = got is not None and verdict(got) == "FAIL"
        finally:
            path.write_text(source)
        good &= caught
        print(f"{'ok ' if caught else 'BAD'} {mid} {'caught' if caught else 'SURVIVED'} by {suite}.{check} ({what})")
    return good


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="vpr-halmos-") as t:
        tmp = pathlib.Path(t)
        good = check_suites(tmp)
        if "--mutants" in sys.argv[1:]:
            good &= check_mutants(tmp)
    print("symbolic checks: all conditions hold" if good else "symbolic checks: FAILED")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
