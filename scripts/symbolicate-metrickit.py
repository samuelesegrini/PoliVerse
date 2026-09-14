#!/usr/bin/env python3
"""Turns the addresses in a MetricKit diagnostic report into function names.

MetricKit call stacks are unsymbolicated by design: each frame carries the
binary's UUID, the frame's address and its offset into the binary's text
segment, which is everything `atos` needs — plus the dSYM of the build that
produced it. See docs/metrickit-performance.md §1.5.

Reads any of the three shapes this project meets:

- iOS 26 `MXDiagnosticPayload.jsonRepresentation()` (the app's archive);
- iOS 27 `DiagnosticReport` encoded with JSONEncoder (the app's archive);
- App Store Connect `diagnosticLogs` (scripts/asc-performance.py).

The walk is by field name rather than by schema, because the iOS 27 encoding
is not documented: any object with `address` and `offsetIntoBinaryTextSegment`
is a frame, `subFrames` are its callees.

Usage:
    scripts/symbolicate-metrickit.py REPORT.json --dsyms PATH [PATH ...]

PATH is a .dSYM, a folder of them, or an .xcarchive. Frames from binaries with
no matching dSYM (system frameworks) are printed as they came.
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys
import uuid as uuidlib
from collections import defaultdict


def parse_int(value):
    if value is None:
        return None
    if isinstance(value, int):
        return value
    text = str(value).strip()
    try:
        return int(text, 16) if text.lower().startswith("0x") else int(text)
    except ValueError:
        return None


def norm_uuid(value):
    try:
        return str(uuidlib.UUID(str(value))).upper()
    except ValueError:
        return None


def binary_names(node, names):
    """iOS 27 keeps binary names apart from frames, in `binaryInfo`.

    A `[UUID: BinaryInfo]` dictionary goes through JSONEncoder as a flat
    [key, value, key, value] array, because its keys are not strings; a
    string-keyed object is accepted too.
    """
    if isinstance(node, dict):
        info = node.get("binaryInfo")
        if isinstance(info, list):
            for item in info:
                if isinstance(item, dict) and "uuid" in item and "name" in item:
                    names[norm_uuid(item["uuid"])] = item["name"]
        elif isinstance(info, dict):
            for key, item in info.items():
                if isinstance(item, dict) and "name" in item:
                    names[norm_uuid(item.get("uuid", key))] = item["name"]
        for child in node.values():
            binary_names(child, names)
    elif isinstance(node, list):
        for child in node:
            binary_names(child, names)


def is_frame(node):
    return isinstance(node, dict) and "address" in node and "offsetIntoBinaryTextSegment" in node


def collect_frames(node, frames):
    if is_frame(node):
        frames.append(node)
    if isinstance(node, dict):
        for child in node.values():
            collect_frames(child, frames)
    elif isinstance(node, list):
        for child in node:
            collect_frames(child, frames)


def dsym_binaries(paths):
    """UUID → DWARF file, for every dSYM under the given paths."""
    found = {}
    for root in paths:
        root = pathlib.Path(root).expanduser()
        candidates = [root] if root.suffix == ".dSYM" else list(root.rglob("*.dSYM"))
        for dsym in candidates:
            for dwarf in (dsym / "Contents" / "Resources" / "DWARF").glob("*"):
                out = subprocess.run(["dwarfdump", "--uuid", str(dwarf)],
                                     capture_output=True, text=True).stdout
                for match in re.finditer(r"UUID: ([0-9A-Fa-f-]{36}) \((\w+)\)", out):
                    found[match.group(1).upper()] = (dwarf, match.group(2))
    return found


def symbolicate(frames, dsyms):
    """Fills `symbol` on every frame whose binary has a dSYM, one atos per binary."""
    by_binary = defaultdict(list)
    for frame in frames:
        key = norm_uuid(frame.get("binaryUUID"))
        address = parse_int(frame.get("address"))
        offset = parse_int(frame.get("offsetIntoBinaryTextSegment"))
        if key in dsyms and address is not None and offset is not None:
            by_binary[key].append((frame, address, address - offset))

    for key, items in by_binary.items():
        dwarf, arch = dsyms[key]
        # One process per load address: a report can hold stacks from more
        # than one launch of the same build, each slid differently.
        by_load = defaultdict(list)
        for frame, address, load in items:
            by_load[load].append((frame, address))
        for load, entries in by_load.items():
            command = ["atos", "-arch", arch, "-o", str(dwarf), "-l", hex(load), "-i"]
            command += [hex(address) for _, address in entries]
            out = subprocess.run(command, capture_output=True, text=True).stdout
            # `-i` prints inlined callers on extra lines, then a blank line
            # between addresses.
            blocks = [b.strip() for b in out.strip().split("\n\n")] if "\n\n" in out else out.strip().splitlines()
            if len(blocks) != len(entries):
                blocks = out.strip().splitlines()[: len(entries)]
            for (frame, _), symbol in zip(entries, blocks):
                frame["symbol"] = symbol.replace("\n", "  ←inlined in  ")


def print_tree(node, names, depth=0, out=sys.stdout):
    if is_frame(node):
        name = node.get("binaryName") or names.get(norm_uuid(node.get("binaryUUID")), "?")
        symbol = node.get("symbol") or node.get("symbolName") or hex(parse_int(node.get("address")) or 0)
        count = node.get("sampleCount")
        suffix = f"  ×{count}" if count and count > 1 else ""
        out.write(f"{'  ' * depth}{name}  {symbol}{suffix}\n")
        for child in node.get("subFrames") or []:
            print_tree(child, names, depth + 1, out)
        return
    if isinstance(node, dict):
        for key, child in node.items():
            if key in ("callStacks", "callStackThreads", "rootFrames", "callStackRootFrames"):
                out.write(f"{'  ' * depth}— {key}\n")
            print_tree(child, names, depth, out)
    elif isinstance(node, list):
        for child in node:
            print_tree(child, names, depth, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("report", type=pathlib.Path)
    parser.add_argument("--dsyms", nargs="+", required=True)
    parser.add_argument("--json", action="store_true",
                        help="write the report back out with a `symbol` on each frame")
    args = parser.parse_args()

    report = json.loads(args.report.read_text())
    names = {}
    binary_names(report, names)
    frames = []
    collect_frames(report, frames)
    if not frames:
        sys.exit("No call stack frames found in the report.")

    dsyms = dsym_binaries(args.dsyms)
    report_uuids = {norm_uuid(f.get("binaryUUID")) for f in frames}
    matched = report_uuids & set(dsyms)
    sys.stderr.write(f"{len(frames)} frames, {len(report_uuids)} binaries, "
                     f"{len(matched)} with a matching dSYM\n")
    if not matched:
        sys.stderr.write("No dSYM matches: is this the archive of the build that sent the report?\n")

    symbolicate(frames, dsyms)
    if args.json:
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print_tree(report, names)


if __name__ == "__main__":
    main()
