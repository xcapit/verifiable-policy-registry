# SPDX-License-Identifier: AGPL-3.0-only
"""Resolver check (VPR-055): a real resolver enforces the compiled zone as `vpr evaluate` predicts.

For each of two zones compiled from the example policy, the check starts the pinned Unbound
container (deploy/unbound/test), queries it with dig and checks that:
  - every name gets the answer that `vpr evaluate` predicts for it: the block page, NXDOMAIN,
    or the upstream address for exceptions and unlisted names;
  - no address of a blocked name (198.51.100.0/24 in upstream.zone) reaches the client;
  - the policy beacon (ADR-0016) is served and `vpr check-beacon` matches it with the version and
    content hash in force, and reports a mismatch for another version; with no beacon in the zone,
    `vpr check-beacon` reports that no beacon answers;
  - the resolver's log contains none of the queried names (no query logging).
Two canaries show that the checks can fail: the resolver serves the zone without its block rules,
and the resolver logs queries. Each must make the corresponding checks fail.
It writes an evidence file and exits 0 if every check passes and every canary is caught, 1
otherwise, 2 on a setup error.
Synthetic data only; nothing leaves the container (the upstream is a local test root zone).
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
POLICY = ROOT / "policies" / "example-primary.yaml"
FEEDS = ROOT / "examples" / "feeds"
TEST_DIR = ROOT / "deploy" / "unbound" / "test"
BLOCK_PAGE = "block.example.org"
BEACON = f"_vpr-policy.{BLOCK_PAGE}"
NAMES = [
    "bad-malware.example",      # category feed
    "www.bad-malware.example",  # subdomain of a listed name
    "c2-server.example",
    "adult-site.example",
    "fake-bank-login.example",
    "casino-example.example",   # local block
    "wikipedia.org",            # exception that is also in a category feed
    "en.wikipedia.org",         # subdomain of an exception
    "khanacademy.org",          # exception
    "unlisted.example",         # not in the policy
]
RUNS = [
    {"run": "block-page-and-beacon", "compile": ["--block-page", BLOCK_PAGE, "--beacon", BLOCK_PAGE], "beacon": True},
    {"run": "nxdomain-without-beacon", "compile": [], "beacon": False},
]
# Each canary breaks one property; the run must then fail exactly the checks named in "expect".
CANARIES = [
    {"run": "canary-block-rules-removed", "compile": RUNS[0]["compile"], "beacon": True,
     "mutate_zone": lambda z: "\n".join(l for l in z.splitlines() if f"CNAME {BLOCK_PAGE}." not in l) + "\n",
     "expect": "resolver answer matches vpr evaluate (redirect)"},
    {"run": "canary-query-logging", "compile": RUNS[0]["compile"], "beacon": True,
     "mutate_conf": lambda c: c.replace("log-queries: no", "log-queries: yes"),
     "expect": "the resolver log contains none of the queried names"},
]
VPR = [sys.executable, "-m", "vpr.cli"]

checks = []
quiet = False


def check(cond, msg, **detail):
    checks.append({"check": msg, "passed": bool(cond), **detail})
    if not quiet:
        print(f"{'ok  ' if cond else 'FAIL'}  {msg}")
    return cond


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def upstream_addresses():
    """Name -> A address from the test root zone."""
    out = {}
    for line in (TEST_DIR / "upstream.zone").read_text().splitlines():
        parts = line.split(";")[0].split()
        if len(parts) == 3 and parts[1] == "A":
            out[parts[0].rstrip(".")] = parts[2]
    return out


def dig(container, name, qtype="A"):
    """Query the resolver inside the container; return (status, [(type, rdata)])."""
    r = sh(["docker", "exec", container, "dig", "@127.0.0.1", "+time=2", "+tries=1", "+noall", "+comments", "+answer", name, qtype])
    status, answers = None, []
    for line in r.stdout.splitlines():
        if "status:" in line:
            status = line.split("status:")[1].split(",")[0].strip()
        elif line and not line.startswith(";"):
            f = line.split(None, 4)
            if len(f) == 5:
                answers.append((f[3], f[4]))
    return status, answers


def expected_ok(action, status, answers, upstream_addr):
    types = {t for t, _ in answers}
    addrs = {d for t, d in answers if t == "A"}
    if action == "redirect":
        return status == "NOERROR" and ("CNAME", BLOCK_PAGE + ".") in answers and addrs == {upstream["block.example.org"]}
    if action == "nxdomain":
        return status == "NXDOMAIN" and "A" not in types
    if action in ("passthru", "allow"):
        return status == "NOERROR" and "CNAME" not in types and addrs == {upstream_addr}
    return False


def wait_ready(container):
    for _ in range(60):
        status, answers = dig(container, BLOCK_PAGE)
        if status == "NOERROR" and answers:
            return True
        time.sleep(0.5)
    return False


def run_one(spec, image, out):
    run_dir = out / spec["run"]
    run_dir.mkdir(parents=True, exist_ok=True)
    zone = run_dir / "policy.rpz"
    r = sh(VPR + ["compile-rpz", str(POLICY), "--feeds-dir", str(FEEDS)] + spec["compile"])
    if r.returncode != 0:
        raise SystemExit(f"setup error: compile-rpz failed: {r.stderr}")
    zone.write_text(r.stdout)
    # predictions always come from the zone as compiled; a canary may serve a mutated copy
    r = sh(VPR + ["evaluate", "--json", str(zone)] + NAMES)
    if r.returncode != 0:
        raise SystemExit(f"setup error: evaluate failed: {r.stderr}")
    predicted = {x["domain"]: x["action"] for x in json.loads(r.stdout)["results"]}
    if "mutate_zone" in spec:
        zone.write_text(spec["mutate_zone"](zone.read_text()))
    conf_path = TEST_DIR / "unbound.conf"
    if "mutate_conf" in spec:
        conf_path = run_dir / "unbound.conf"
        conf_path.write_text(spec["mutate_conf"]((TEST_DIR / "unbound.conf").read_text()))

    container = f"vpr-resolver-{spec['run']}"
    sh(["docker", "rm", "-f", container])
    r = sh([
        "docker", "run", "-d", "--name", container, "--network", "none",
        "-v", f"{run_dir}:/zones:ro",
        "-v", f"{conf_path}:/etc/unbound/unbound.conf:ro",
        "-v", f"{TEST_DIR / 'upstream.zone'}:/etc/unbound/upstream.zone:ro",
        image,
    ])
    if r.returncode != 0:
        raise SystemExit(f"setup error: docker run failed: {r.stderr}")
    result = {"run": spec["run"], "zoneSha256": hashlib.sha256(zone.read_bytes()).hexdigest(), "names": []}
    try:
        conf = sh(["docker", "exec", container, "unbound-checkconf", "/etc/unbound/unbound.conf"])
        check(conf.returncode == 0, f"[{spec['run']}] unbound-checkconf accepts the test configuration", output=conf.stdout.strip())
        if not check(wait_ready(container), f"[{spec['run']}] resolver answers"):
            print(sh(["docker", "logs", container]).stderr, file=sys.stderr)
            return result

        for name in NAMES:
            status, answers = dig(container, name)
            action = predicted[name]
            ok = expected_ok(action, status, answers, upstream.get(name))
            leaked = [d for t, d in answers if t == "A" and d.startswith("198.51.100.")]
            check(ok and not leaked, f"[{spec['run']}] {name}: resolver answer matches vpr evaluate ({action})",
                  status=status, answers=answers)
            result["names"].append({"name": name, "predicted": action, "status": status, "answers": answers})

        status, answers = dig(container, BEACON, "TXT")
        txt = " ".join(d for t, d in answers if t == "TXT")
        result["beacon"] = {"status": status, "txt": txt}
        policy_hash = sh(VPR + ["policy-hash", str(POLICY)]).stdout
        content = next(l.split()[1] for l in policy_hash.splitlines() if l.startswith("contentHash:"))
        version = next(l.split()[1] for l in policy_hash.splitlines() if l.startswith("version:"))
        match = sh(VPR + ["check-beacon", str(POLICY), "--txt", txt, "--version", version, "--content-hash", content])
        if spec["beacon"]:
            check(match.returncode == 0, f"[{spec['run']}] beacon is served and vpr check-beacon matches it (exit 0)", output=match.stdout.strip())
            stale = sh(VPR + ["check-beacon", str(POLICY), "--txt", txt, "--version", str(int(version) + 1), "--content-hash", content])
            check(stale.returncode == 1, f"[{spec['run']}] vpr check-beacon reports a stale zone when another version is in force (exit 1)", output=stale.stdout.strip())
        else:
            check(match.returncode == 1 and not txt, f"[{spec['run']}] no beacon answers and vpr check-beacon reports it (exit 1)", output=match.stdout.strip())

        logs = sh(["docker", "logs", container])
        text = (logs.stdout + logs.stderr).lower()
        found = [n for n in NAMES + [BEACON] if n.lower() in text]
        check(not found, f"[{spec['run']}] the resolver log contains none of the queried names", logLines=len(text.splitlines()), found=found)
        (run_dir / "resolver.log").write_text(logs.stdout + logs.stderr)
    finally:
        sh(["docker", "rm", "-f", container])
    return result


def main():
    global upstream, checks, quiet
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--image", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()
    out = pathlib.Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    upstream = upstream_addresses()

    version = sh(["docker", "run", "--rm", "--entrypoint", "/usr/local/sbin/unbound", a.image, "-V"]).stdout.splitlines()
    image_id = sh(["docker", "image", "inspect", "--format", "{{.Id}}", a.image]).stdout.strip()
    if not version or not image_id:
        print("setup error: resolver image not available", file=sys.stderr)
        return 2
    runs = [run_one(spec, a.image, out) for spec in RUNS]
    passed = all(c["passed"] for c in checks)

    canaries = []
    print()
    for spec in CANARIES:
        main_checks, checks, quiet = checks, [], True
        run_one(spec, a.image, out)
        failed = [c["check"] for c in checks if not c["passed"]]
        caught = bool(failed) and all(spec["expect"] in f for f in failed)
        checks, quiet = main_checks, False
        print(f"{'ok  ' if caught else 'FAIL'}  canary {spec['run']} is caught ({len(failed)} checks fail, all of them '{spec['expect']}')")
        canaries.append({"canary": spec["run"], "caught": caught, "failedChecks": failed})
    passed = passed and all(c["caught"] for c in canaries)
    evidence = {
        "evidenceFormat": "vpr-resolver-evidence/1",
        "result": "passed" if passed else "failed",
        "resolver": {"version": version[0], "build": version[1:], "imageId": image_id},
        "policy": str(POLICY.relative_to(ROOT)),
        "runs": runs,
        "checks": checks,
        "canaries": canaries,
        "limitations": [
            "Synthetic data; the upstream is a local test root zone, so no query leaves the container.",
            "One resolver implementation (Unbound); a second one is planned (VPR-062).",
            "The test configuration keeps the RPZ, module and logging settings of deploy/unbound/rpz.conf but not its TLS listeners or access ranges.",
        ],
    }
    (out / "resolver-evidence.json").write_text(json.dumps(evidence, indent=2))
    print(f"\n{sum(c['passed'] for c in checks)}/{len(checks)} checks passed, {sum(c['caught'] for c in canaries)}/{len(canaries)} canaries caught. Evidence: {out / 'resolver-evidence.json'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
