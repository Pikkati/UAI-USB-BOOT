#!/usr/bin/env python3
"""Fetch build logs for the most recent successful build and save to file.

Usage: python fetch_build_logs.py --service <svc> --api-key <key> --out build.log

Tries multiple endpoints to retrieve logs and falls back to events capture if logs not available.
"""

import argparse
import json
import sys

import requests


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--service", required=True)
    p.add_argument("--api-key", required=True)
    p.add_argument("--out", default="build.log")
    args = p.parse_args()

    headers = {"Authorization": f"Bearer {args.api_key}"}

    # Get recent events and find last build_ended succeeded
    ev_url = f"https://api.render.com/v1/services/{args.service}/events"
    er = requests.get(ev_url, headers=headers, timeout=30)
    if er.status_code != 200:
        print("Failed to fetch events", er.status_code, er.text[:1000])
        return 2
    events = er.json()
    build_id = None
    for item in events:
        evt = item.get("event", {})
        if (
            evt.get("type") == "build_ended"
            and evt.get("details", {}).get("buildStatus") == "succeeded"
        ):
            build_id = evt.get("details", {}).get("buildId")
            break

    if not build_id:
        print("No successful build found in events; saving recent events as fallback")
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(events[:50], indent=2))
        return 0

    print("Found build id:", build_id)

    # Try known logs endpoints
    candidates = [
        f"https://api.render.com/v1/builds/{build_id}/logs",
        f"https://api.render.com/v1/services/{args.service}/builds/{build_id}/logs",
    ]

    for url in candidates:
        print("Trying", url)
        r = requests.get(url, headers=headers, timeout=30)
        if r.status_code == 200:
            # render returns text or json; save raw
            with open(args.out, "wb") as fh:
                if isinstance(r.content, bytes):
                    fh.write(r.content)
                else:
                    fh.write(r.text.encode("utf-8"))
            print("Saved logs to", args.out)
            return 0
        print("no logs at", url, "status", r.status_code)

    print("Could not find build logs; saving events as fallback")
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(events[:50], indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
