#!/usr/bin/env python3
"""List ROCm nightly tarball URLs for a given platform and GPU target."""

import argparse
import re
import urllib.request

S3_BASE = "https://therock-nightly-tarball.s3.amazonaws.com/"


def parse_version(v):
    """Parse version string into sortable tuple: (major, minor, patch, is_prerelease, prerelease_num)"""
    m = re.match(r"(\d+)\.(\d+)\.(\d+)(a|rc)?(\d+)?$", v)
    if not m:
        return (0, 0, 0, 1, 0)
    major, minor, patch, pre_type, pre_num = m.groups()
    # alpha < rc < release: alpha=0, rc=1, release=2
    pre_order = 2 if not pre_type else (0 if pre_type == "a" else 1)
    return (int(major), int(minor), int(patch), pre_order, int(pre_num or 0))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("-p", "--platform", default="linux", choices=["linux", "windows"])
    p.add_argument("-t", "--target", default="gfx1151")
    p.add_argument("-c", "--count", type=int, default=5)
    p.add_argument("-q", "--quiet", action="store_true")
    args = p.parse_args()

    # Map target for S3 prefix
    s3_target = args.target
    if args.target == "gfx110X":
        s3_target += "-dgpu"
    elif args.target == "gfx120X":
        s3_target += "-all"

    prefix = f"therock-dist-{args.platform}-{s3_target}-7"
    pattern = re.compile(
        rf"{re.escape(prefix[:-2])}-(\d+\.\d+\.\d+(?:a\d+|rc\d+)?)\.tar\.gz$"
    )

    if not args.quiet:
        print(f"Fetching S3 listing for prefix: {prefix} ...")

    with urllib.request.urlopen(f"{S3_BASE}?prefix={prefix}") as resp:
        data = resp.read().decode()

    # Extract keys and versions
    candidates = []
    for key in re.findall(r"<Key>([^<]+)</Key>", data):
        if m := pattern.search(key):
            candidates.append((parse_version(m.group(1)), key))

    # Sort by version descending and take newest
    candidates.sort(reverse=True)
    newest = candidates[: args.count] if candidates else []

    if not args.quiet:
        print(f"Showing {len(newest)} newest candidate(s):")
    for _, key in newest:
        print(f"{S3_BASE}{key}")


if __name__ == "__main__":
    main()
