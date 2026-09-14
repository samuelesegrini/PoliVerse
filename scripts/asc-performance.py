#!/usr/bin/env python3
"""Downloads PoliVerse's field performance data from the App Store Connect API.

The same numbers Xcode's Organizer shows — launch, hangs, memory, disk writes,
battery, terminations, per app version — and the diagnostic signatures behind
them, with call-stack logs. Aggregated by Apple from users who share analytics
with developers; nothing here involves the app itself.
See docs/metrickit-performance.md §2 and Phase 4, and docs/field-performance.md.

Credentials come from the environment and are never printed or written:

    ASC_KEY_ID      the API key's ID
    ASC_ISSUER_ID   the issuer ID shown above the key list
    ASC_KEY_PATH    path to the downloaded AuthKey_<id>.p8

Create the key in App Store Connect → Users and Access → Integrations →
App Store Connect API, with at least the Developer role.

Usage:
    scripts/asc-performance.py metrics    [--bundle-id ID] [--out DIR]
    scripts/asc-performance.py signatures --build NUMBER [--bundle-id ID]
                                          [--type HANGS|DISK_WRITES|LAUNCHES]
                                          [--top N] [--out DIR]

Only the standard library and `openssl` (preinstalled on macOS) are needed.
"""

import argparse
import base64
import datetime
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE_ID = "segrini.samuele.PoliVerse"


# MARK: Token

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(signature: bytes) -> bytes:
    """ES256 in a JWT is r‖s, 32 bytes each; `openssl dgst -sign` writes DER."""
    def read_int(buf, i):
        assert buf[i] == 0x02, "malformed DER signature"
        length = buf[i + 1]
        value = buf[i + 2 : i + 2 + length]
        return int.from_bytes(value, "big"), i + 2 + length

    assert signature[0] == 0x30, "malformed DER signature"
    offset = 2 if signature[1] < 0x80 else 3
    r, offset = read_int(signature, offset)
    s, _ = read_int(signature, offset)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def make_token(key_id: str, issuer_id: str, key_path: str, lifetime: int = 1200) -> str:
    """A JWT as App Store Connect requires: ES256, `appstoreconnect-v1`, at most 20 minutes."""
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + min(lifetime, 1200), "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}." \
                    f"{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True)
    if result.returncode != 0:
        sys.exit("openssl could not sign with ASC_KEY_PATH: " + result.stderr.decode().strip())
    return f"{signing_input}.{b64url(der_to_raw(result.stdout))}"


# MARK: API

class Client:
    def __init__(self):
        missing = [name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(name)]
        if missing:
            sys.exit("Missing environment: " + ", ".join(missing) + " (see --help)")
        self.credentials = (os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"],
                            os.path.expanduser(os.environ["ASC_KEY_PATH"]))
        self.token, self.issued = None, 0

    def get(self, path, query=None, accept="application/json"):
        # Renewed well before its 20 minutes: a signature download can be slow.
        if not self.token or time.time() - self.issued > 900:
            self.token, self.issued = make_token(*self.credentials), time.time()
        url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
        request = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {self.token}", "Accept": accept})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            body = error.read().decode(errors="replace")[:600]
            sys.exit(f"GET {path} → HTTP {error.code}\n{body}")

    def app_id(self, bundle_id):
        data = self.get("/v1/apps", {"filter[bundleId]": bundle_id, "fields[apps]": "bundleId,name"})
        apps = data.get("data", [])
        if not apps:
            sys.exit(f"No app with bundle ID {bundle_id} visible to this key.")
        return apps[0]["id"]

    def build_id(self, app_id, number):
        data = self.get("/v1/builds", {
            "filter[app]": app_id, "filter[version]": number,
            "sort": "-uploadedDate", "limit": "1", "fields[builds]": "version,uploadedDate"})
        builds = data.get("data", [])
        if not builds:
            sys.exit(f"No build {number} found for this app.")
        return builds[0]["id"]


# MARK: Output

def write(out_dir, name, data):
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / name
    path.write_text(json.dumps(data, indent=2))
    return path


def summarise_metrics(data):
    lines = []
    insights = data.get("insights") or {}
    for kind in ("regressions", "trendingUp"):
        for insight in insights.get(kind) or []:
            flag = "!" if insight.get("highImpact") else "·"
            lines.append(f"{flag} {kind}: {insight.get('summaryString') or insight.get('metric')}")
    for product in data.get("productData") or []:
        for category in product.get("metricCategories") or []:
            lines.append(f"\n{category.get('identifier')}")
            for metric in category.get("metrics") or []:
                unit = (metric.get("unit") or {}).get("displayName", "")
                for dataset in metric.get("datasets") or []:
                    criteria = dataset.get("filterCriteria") or {}
                    if criteria.get("device") not in (None, "all_iphones", "all"):
                        continue
                    points = dataset.get("points") or []
                    if not points:
                        continue
                    latest = points[-1]
                    previous = points[-2] if len(points) > 1 else None
                    change = ""
                    if previous and previous.get("value"):
                        delta = (latest["value"] - previous["value"]) / previous["value"] * 100
                        change = f"  ({delta:+.0f}% vs {previous.get('version')})"
                    goal = f"  goal: {latest['goal']}" if latest.get("goal") else ""
                    lines.append(f"  {metric.get('identifier'):<34} {criteria.get('percentile', ''):<8} "
                                 f"{latest.get('value')} {unit} @ {latest.get('version')}{change}{goal}")
    return "\n".join(lines)


# MARK: Commands

def cmd_metrics(client, args):
    app = client.app_id(args.bundle_id)
    data = client.get(f"/v1/apps/{app}/perfPowerMetrics",
                      {"filter[platform]": "IOS"}, accept="application/vnd.apple.xcode-metrics+json")
    stamp = datetime.date.today().isoformat()
    path = write(args.out, f"metrics-{stamp}.json", data)
    print(summarise_metrics(data))
    print(f"\nSaved {path}")


def cmd_signatures(client, args):
    app = client.app_id(args.bundle_id)
    build = client.build_id(app, args.build)
    query = {"fields[diagnosticSignatures]": "diagnosticType,signature,weight,insight", "limit": "200"}
    if args.type:
        query["filter[diagnosticType]"] = args.type
    signatures = client.get(f"/v1/builds/{build}/diagnosticSignatures", query).get("data", [])
    signatures.sort(key=lambda item: item.get("attributes", {}).get("weight") or 0, reverse=True)
    out = args.out / f"build-{args.build}"
    write(out, "signatures.json", signatures)

    if not signatures:
        print("No diagnostic signatures for this build (yet): Apple needs enough devices reporting.")
        return
    for rank, item in enumerate(signatures[: args.top], 1):
        attributes = item.get("attributes", {})
        weight = attributes.get("weight") or 0
        print(f"{rank}. [{attributes.get('diagnosticType')}] {weight:.1%}  {attributes.get('signature')}")
        logs = client.get(f"/v1/diagnosticSignatures/{item['id']}/logs", {"limit": "5"},
                          accept="application/vnd.apple.diagnostic-logs+json")
        path = write(out, f"{rank:02d}-{attributes.get('diagnosticType', 'log').lower()}-logs.json", logs)
        for product in logs.get("productData") or []:
            for insight in product.get("diagnosticInsights") or []:
                print(f"   insight: {insight.get('insightsString')}")
        print(f"   logs: {path}")
    print(f"\nSymbolicate with: scripts/symbolicate-metrickit.py <logs.json> --dsyms <archive>")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("build/field-performance"),
                        help="where JSON is saved (default: build/field-performance, git-ignored)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("metrics", help="per-version metrics and Apple's regression insights")
    signatures = sub.add_parser("signatures", help="top diagnostic signatures of a build, with logs")
    signatures.add_argument("--build", required=True, help="build number (CFBundleVersion)")
    signatures.add_argument("--type", choices=["HANGS", "DISK_WRITES", "LAUNCHES"])
    signatures.add_argument("--top", type=int, default=5)
    args = parser.parse_args()

    client = Client()
    {"metrics": cmd_metrics, "signatures": cmd_signatures}[args.command](client, args)


if __name__ == "__main__":
    main()
