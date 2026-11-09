"""Policy documents: validation, canonical form, content hash and RPZ compilation.

A policy document is the public, human-readable description of what a scope blocks and why.
Its keccak256 over the canonical JSON form is the `contentHash` published on-chain.

Restricted lists (for example the IWF URL List) are never included in the public document.
They are referenced only by a commitment (`restricted_list_hash`) and merged at compile time
by the operator.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import yaml

from .hashing import keccak256, to_hex

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?!-)([a-z0-9-]{1,63}(?<!-)\.)+[a-z]{2,63}$")

# Reason codes shared with the on-chain registry (docs/GOVERNANCE.md).
REASON_CODES = {
    1: "initial_policy",
    2: "scheduled_renewal",
    3: "appeal_accepted",
    4: "new_threat",
    5: "legal_requirement",
    6: "correction",
}

REQUIRED_KEYS = {"scope", "version", "profile", "categories", "local_blocks", "exceptions"}


class PolicyError(ValueError):
    pass


@dataclass(frozen=True)
class Policy:
    doc: dict

    @property
    def scope(self) -> str:
        return self.doc["scope"]

    def canonical_json(self) -> bytes:
        """Deterministic JSON: sorted keys, no whitespace, UTF-8."""
        return json.dumps(self.doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

    def content_hash(self) -> str:
        return to_hex(keccak256(self.canonical_json()))

    def scope_id(self) -> str:
        """bytes32 scope id used on-chain: keccak256 of the scope string."""
        return to_hex(keccak256(self.scope.encode("utf-8")))


def _check_domain(d: str, where: str) -> str:
    d = d.strip().lower().rstrip(".")
    if not DOMAIN_RE.match(d):
        raise PolicyError(f"invalid domain {d!r} in {where}")
    return d


def validate(doc: dict) -> Policy:
    missing = REQUIRED_KEYS - set(doc)
    if missing:
        raise PolicyError(f"missing keys: {sorted(missing)}")
    if not isinstance(doc["categories"], list) or not all(isinstance(c, str) for c in doc["categories"]):
        raise PolicyError("categories must be a list of strings")
    for section in ("local_blocks", "exceptions"):
        entries = doc[section]
        if not isinstance(entries, list):
            raise PolicyError(f"{section} must be a list")
        for i, e in enumerate(entries):
            if not isinstance(e, dict) or "domain" not in e or "reason" not in e:
                raise PolicyError(f"{section}[{i}] needs 'domain' and 'reason' (every entry must say why)")
            e["domain"] = _check_domain(e["domain"], f"{section}[{i}]")
            if not str(e["reason"]).strip():
                raise PolicyError(f"{section}[{i}] has an empty reason")
    blocked = {e["domain"] for e in doc["local_blocks"]}
    allowed = {e["domain"] for e in doc["exceptions"]}
    overlap = blocked & allowed
    if overlap:
        raise PolicyError(f"domains both blocked and excepted: {sorted(overlap)}")
    rlh = doc.get("restricted_list_hash")
    if rlh is not None and not re.fullmatch(r"0x[0-9a-f]{64}", str(rlh)):
        raise PolicyError("restricted_list_hash must be a 0x-prefixed 32-byte hex string")
    return Policy(doc)


def load(path: str | Path) -> Policy:
    with open(path, encoding="utf-8") as f:
        return validate(yaml.safe_load(f))


def load_feed(path: str | Path) -> list[str]:
    """One domain per line; '#' comments allowed. Used for threat feeds and category lists."""
    out = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(_check_domain(line, str(path)))
    return out


def compile_rpz(
    policy: Policy,
    feeds: dict[str, list[str]] | None = None,
    restricted: list[str] | None = None,
    block_page: str | None = None,
    serial: int | None = None,
) -> str:
    """Compile a policy into an RPZ zone (RFC-draft Response Policy Zones), usable by Unbound or PowerDNS.

    - Domains from `local_blocks`, the selected category feeds and the restricted list are blocked.
    - `exceptions` are emitted as PASSTHRU rules, which take precedence.
    - If `block_page` is given, blocked names are redirected there (so users see a notice and can appeal);
      otherwise they get NXDOMAIN.
    """
    feeds = feeds or {}
    blocked: dict[str, str] = {}
    for cat in policy.doc["categories"]:
        for d in feeds.get(cat, []):
            blocked.setdefault(d, f"category:{cat}")
    for e in policy.doc["local_blocks"]:
        blocked[e["domain"]] = "local"
    for d in restricted or []:
        blocked[_check_domain(d, "restricted")] = "restricted"
    exceptions = sorted(e["domain"] for e in policy.doc["exceptions"])
    for d in exceptions:
        blocked.pop(d, None)

    serial = serial or int(datetime.now(timezone.utc).strftime("%Y%m%d%H"))
    target = f"{block_page.rstrip('.')}." if block_page else "."
    lines = [
        f"; RPZ generated by vpr for scope {policy.scope} version {policy.doc['version']}",
        f"; policy content hash {policy.content_hash()}",
        "$TTL 300",
        f"@ SOA localhost. hostmaster.localhost. {serial} 3600 600 86400 300",
        "@ NS localhost.",
        "",
        "; exceptions (PASSTHRU)",
    ]
    for d in exceptions:
        lines += [f"{d} CNAME rpz-passthru.", f"*.{d} CNAME rpz-passthru."]
    lines += ["", "; blocks"]
    for d in sorted(blocked):
        source = "" if blocked[d] == "restricted" else f" ; {blocked[d]}"
        lines += [f"{d} CNAME {target}{source}", f"*.{d} CNAME {target}"]
    return "\n".join(lines) + "\n"


def restricted_list_hash(domains: list[str]) -> str:
    """Commitment to a restricted list: keccak256 of the sorted, newline-joined domains."""
    norm = sorted({_check_domain(d, "restricted") for d in domains})
    return to_hex(keccak256("\n".join(norm).encode("utf-8")))
