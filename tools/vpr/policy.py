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
from pathlib import Path

import yaml

from .hashing import keccak256, scope_id, to_hex

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
OPTIONAL_KEYS = {"valid_days", "reason_code", "threat_feeds", "restricted_list_hash", "feed_hashes"}
PROFILES = {"primary", "secondary", "teachers"}
SCOPE_RE = re.compile(r"[a-z0-9-]+:[A-Z]{2}:[a-z0-9-]+")  # used with fullmatch
CATEGORY_RE = re.compile(r"[a-z0-9_-]{1,64}")  # used with fullmatch


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

    def scope_id(self, governor: str) -> str:
        """bytes32 scope id used on-chain: keccak256(abi.encode(governor, scope)) (VerifiablePolicyRegistry.scopeIdOf)."""
        return scope_id(governor, self.scope)


def _check_domain(d: str, where: str) -> str:
    if not isinstance(d, str):
        raise PolicyError(f"domain in {where} must be a string")
    d = d.strip().lower().removesuffix(".")
    if not DOMAIN_RE.fullmatch(d):
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
    if not isinstance(doc["scope"], str) or not SCOPE_RE.fullmatch(doc["scope"]):
        raise PolicyError("scope must look like <programme>:<CC>:<profile>, e.g. giga:AR:primary")
    if not _is_int(doc["version"]) or doc["version"] < 1:
        raise PolicyError("version must be an integer >= 1")
    if doc["profile"] not in PROFILES:
        raise PolicyError(f"profile must be one of {sorted(PROFILES)}")
    cats = doc["categories"]
    if not isinstance(cats, list) or not all(isinstance(c, str) and CATEGORY_RE.fullmatch(c) for c in cats):
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
            if not isinstance(e["reason"], str) or not e["reason"].strip():
                raise PolicyError(f"{section}[{i}] has an empty reason")
    blocked = {e["domain"] for e in doc["local_blocks"]}
    allowed = {e["domain"] for e in doc["exceptions"]}
    overlap = blocked & allowed
    if overlap:
        raise PolicyError(f"domains both blocked and excepted: {sorted(overlap)}")
    fh = doc.get("feed_hashes")
    if fh is not None:
        if not isinstance(fh, dict) or set(fh) != set(cats):
            raise PolicyError("feed_hashes must map every category, and only those, to a feed hash")
        if not all(isinstance(v, str) and re.fullmatch(r"0x[0-9a-f]{64}", v) for v in fh.values()):
            raise PolicyError("feed hashes must be 0x-prefixed 32-byte hex strings")
    rlh = doc.get("restricted_list_hash")
    if rlh is not None and not re.fullmatch(r"0x[0-9a-f]{64}", str(rlh)):
        raise PolicyError("restricted_list_hash must be a 0x-prefixed 32-byte hex string")
    return Policy(doc)


class _UniqueKeyLoader(yaml.SafeLoader):
    """Safe loader that rejects duplicate keys, so the document that is reviewed is the document that is hashed."""

    def construct_mapping(self, node, deep=False):
        keys = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in keys:
                raise PolicyError(f"duplicate key {key!r} in policy document")
            keys.add(key)
        return super().construct_mapping(node, deep=deep)


def load(path: str | Path) -> Policy:
    with open(path, encoding="utf-8") as f:
        try:
            doc = yaml.load(f, Loader=_UniqueKeyLoader)
        except yaml.YAMLError as e:
            raise PolicyError(f"not a valid YAML or JSON policy document: {getattr(e, 'problem', e)}") from None
    return validate(doc)


def load_feed(path: str | Path) -> list[str]:
    """One domain per line; '#' comments allowed. Used for threat feeds, category lists and restricted lists.

    Errors report the line number only, never the entry: restricted lists must not leak through error output.
    """
    out = []
    for n, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        line = line.split("#", 1)[0].strip()
        if line:
            d = line.lower().removesuffix(".")
            if not DOMAIN_RE.fullmatch(d):
                raise PolicyError(f"invalid domain at line {n} of {Path(path).name}")
            out.append(d)
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
    missing = [c for c in policy.doc["categories"] if not feeds.get(c)]
    if missing and not allow_missing_feeds:
        raise PolicyError(f"no feed, or an empty feed, for categories {missing}: refusing to compile a zone without promised protection")
    if block_page is not None:
        block_page = _check_domain(block_page, "block_page")
    declared_feeds = policy.doc.get("feed_hashes")
    if declared_feeds:
        for cat in policy.doc["categories"]:
            if cat in feeds and list_hash(feeds[cat]) != declared_feeds[cat]:
                raise PolicyError(f"feed for category {cat!r} does not match the hash declared in the policy")
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
    restricted_set = set()
    for i, d in enumerate(restricted or [], start=1):
        dn = d.strip().lower().removesuffix(".")
        if not DOMAIN_RE.fullmatch(dn):
            raise PolicyError(f"invalid entry {i} in the restricted list")
        restricted_set.add(dn)
        blocked[dn] = "restricted"
    exceptions = sorted(e["domain"] for e in policy.doc["exceptions"])
    for x in exceptions:
        # an exception must never cancel a restricted entry, exactly or through a parent domain;
        # the error does not name the entry
        if any(r == x or r.endswith("." + x) for r in restricted_set):
            raise PolicyError("an exception covers an entry of the restricted list; refusing to compile")
    for d in exceptions:
        blocked.pop(d, None)

    # deterministic: the serial derives from the policy version unless given explicitly
    serial = serial or int(policy.doc["version"])
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


def list_hash(domains: list[str]) -> str:
    """Commitment to a domain list: keccak256 of the sorted, unique, normalised domains joined by newlines.
    Used for restricted lists and for category feeds (feed_hashes)."""
    return restricted_list_hash(domains)


def zone_hash(zone: str) -> str:
    """keccak256 of a compiled zone's bytes; the value a deployment attestation records as resolverConfigHash."""
    return to_hex(keccak256(zone.encode("utf-8")))


def restricted_list_hash(domains: list[str]) -> str:
    """Commitment to a restricted list: keccak256 of the sorted, newline-joined domains.
    Errors give the position only, never the entry."""
    norm_set = set()
    for i, d in enumerate(domains, start=1):
        dn = d.strip().lower().removesuffix(".") if isinstance(d, str) else ""
        if not DOMAIN_RE.fullmatch(dn):
            raise PolicyError(f"invalid entry {i} in the list")
        norm_set.add(dn)
    norm = sorted(norm_set)
    return to_hex(keccak256("\n".join(norm).encode("utf-8")))


_RPZ_ACTIONS = {"rpz-passthru.": "passthru", ".": "nxdomain", "*.": "nodata", "rpz-drop.": "drop", "rpz-tcp-only.": "tcp-only"}


def evaluate_zone(zone: str, domain: str) -> dict:
    """Evaluate a domain against a compiled RPZ zone (as produced by `compile_rpz`).

    This is a zone evaluation, not DNS resolution: it applies RPZ QNAME-trigger precedence (an exact owner
    name wins over wildcards, and a more specific wildcard wins over a less specific one) to the zone text,
    so the artefact that a resolver would load is what gets tested. It does not query any resolver.

    It fails closed on input it does not understand: any record other than the zone header ($TTL, SOA, NS
    at the apex) and CNAME triggers raises PolicyError instead of being ignored.
    """
    name = _check_domain(domain, "query")
    exact: dict[str, tuple[str, str]] = {}
    wild: dict[str, tuple[str, str]] = {}
    for n, line in enumerate(zone.splitlines(), start=1):
        body, _, comment = line.partition(";")
        parts = body.split()
        if not parts or parts[0].upper() == "$TTL" or parts[0] == "@":
            continue
        owner = parts[0].lower().removesuffix(".")
        rest = parts[1:]
        if rest and rest[0].isdigit():
            rest = rest[1:]  # TTL
        if rest and rest[0].upper() == "IN":
            rest = rest[1:]
        if len(rest) != 2 or rest[0].upper() != "CNAME":
            raise PolicyError(f"unsupported record at line {n} of the zone")
        target = rest[1].lower()
        rule = (target, comment.strip() or "unlabelled")
        if owner.startswith("*."):
            wild[owner[2:]] = rule
        else:
            exact[owner] = rule
    match, rule = None, None
    if name in exact:
        match, rule = name, exact[name]
    else:
        labels = name.split(".")
        for i in range(1, len(labels)):
            parent = ".".join(labels[i:])
            if parent in wild:
                target, source = wild[parent]
                # compile_rpz labels the exact owner line only; the wildcard inherits that label
                if source == "unlabelled" and parent in exact:
                    source = exact[parent][1]
                match, rule = f"*.{parent}", (target, source)
                break
    if rule is None:
        return {"domain": name, "action": "allow", "rule": None, "source": None}
    target, source = rule
    action = _RPZ_ACTIONS.get(target, "redirect")
    return {"domain": name, "action": action, "rule": match, "source": None if action == "passthru" else source}
