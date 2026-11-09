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
OPTIONAL_KEYS = {"valid_days", "reason_code", "threat_feeds", "restricted_list_hash"}
PROFILES = {"primary", "secondary", "teachers"}
SCOPE_RE = re.compile(r"^[a-z0-9-]+:[A-Z]{2}:[a-z0-9-]+$")
CATEGORY_RE = re.compile(r"^[a-z0-9_-]+$")


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


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def validate(doc: dict) -> Policy:
    """Validate a policy document against format 1 (same rules as schemas/policy.schema.json)."""
    if not isinstance(doc, dict):
        raise PolicyError("policy document must be a mapping")
    missing = REQUIRED_KEYS - set(doc)
    if missing:
        raise PolicyError(f"missing keys: {sorted(missing)}")
    unknown = set(doc) - REQUIRED_KEYS - OPTIONAL_KEYS
    if unknown:
        raise PolicyError(f"unknown keys: {sorted(unknown)}")
    if not isinstance(doc["scope"], str) or not SCOPE_RE.match(doc["scope"]):
        raise PolicyError("scope must look like <programme>:<CC>:<profile>, e.g. giga:AR:primary")
    if not _is_int(doc["version"]) or doc["version"] < 1:
        raise PolicyError("version must be an integer >= 1")
    if doc["profile"] not in PROFILES:
        raise PolicyError(f"profile must be one of {sorted(PROFILES)}")
    cats = doc["categories"]
    if not isinstance(cats, list) or not all(isinstance(c, str) and CATEGORY_RE.match(c) for c in cats):
        raise PolicyError("categories must be a list of lowercase identifiers")
    if len(cats) != len(set(cats)):
        raise PolicyError("categories must not repeat")
    if "valid_days" in doc and (not _is_int(doc["valid_days"]) or doc["valid_days"] < 1):
        raise PolicyError("valid_days must be an integer >= 1")
    if "reason_code" in doc and doc["reason_code"] not in REASON_CODES:
        raise PolicyError(f"reason_code must be one of {sorted(REASON_CODES)}")
    feeds = doc.get("threat_feeds", [])
    if not isinstance(feeds, list) or not all(
        isinstance(f, dict) and set(f) == {"provider", "version"} and all(isinstance(v, str) and v for v in f.values())
        for f in feeds
    ):
        raise PolicyError("threat_feeds entries need exactly a non-empty provider and version")
    for section in ("local_blocks", "exceptions"):
        entries = doc[section]
        if not isinstance(entries, list):
            raise PolicyError(f"{section} must be a list")
        for i, e in enumerate(entries):
            if not isinstance(e, dict) or set(e) != {"domain", "reason"}:
                raise PolicyError(f"{section}[{i}] needs exactly 'domain' and 'reason' (every entry must say why)")
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
    allow_missing_feeds: bool = False,
) -> str:
    """Compile a policy into an RPZ zone (RFC-draft Response Policy Zones), usable by Unbound or PowerDNS.

    - Domains from `local_blocks`, the selected category feeds and the restricted list are blocked.
    - `exceptions` are emitted as PASSTHRU rules, which take precedence.
    - If `block_page` is given, blocked names are redirected there (so users see a notice and can appeal);
      otherwise they get NXDOMAIN.
    - Fails closed: a category without a feed, or a restricted list whose hash differs from the one declared in
      the policy, is an error rather than a silently weaker zone.
    """
    feeds = feeds or {}
    missing = [c for c in policy.doc["categories"] if c not in feeds]
    if missing and not allow_missing_feeds:
        raise PolicyError(f"no feed for categories {missing}: refusing to compile a zone without promised protection")
    declared = policy.doc.get("restricted_list_hash")
    if declared and restricted is None:
        raise PolicyError("the policy declares a restricted list but none was supplied")
    if restricted is not None:
        if not declared:
            raise PolicyError("a restricted list was supplied but the policy does not declare its hash")
        actual = restricted_list_hash(restricted)
        if actual != declared:
            raise PolicyError(f"restricted list hash {actual} does not match the policy ({declared})")
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
