#!/usr/bin/env python3
"""Wait for the most recent deploy of a Render service to become live or fail.

Usage: python wait_for_render_deploy.py --service <svc> --api-key <key> --timeout 600

Exits with 0 on success, 2 on failed deploy, 3 on timeout.
Prints deploy and build ids for downstream steps.
"""

import argparse
import time
import requests
import sys
import json


def get_latest_deploy(api_key, service_id):
    url = f"https://api.render.com/v1/services/{service_id}/deploys"
    r = requests.get(url, headers={"Authorization": f"Bearer {api_key}"}, timeout=30)
    if r.status_code != 200:
        return None
    arr = r.json()
    if not arr:
        return None
    return arr[0].get("deploy")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--service", required=True)
    p.add_argument("--api-key", required=True)
    p.add_argument("--timeout", type=int, default=600)
    args = p.parse_args()

    start = time.time()
    last_status = None
    print(f"Waiting up to {args.timeout}s for deploy to become live...")
    while time.time() - start < args.timeout:
        d = get_latest_deploy(args.api_key, args.service)
        if not d:
            print("No deploys yet. Sleeping 5s...")
            time.sleep(5)
            continue
        status = d.get("status")
        if status != last_status:
            print("Deploy status:", status)
            last_status = status
        if status in ("success", "live"):
            print("Deploy is live.")
            # try to find build id from service events
            # fetch events
            ev = requests.get(
                f"https://api.render.com/v1/services/{args.service}/events",
                headers={"Authorization": f"Bearer {args.api_key}"},
                timeout=30,
            )
            if ev.status_code == 200:
                events = ev.json()
                # find first build_ended success event
                for item in events:
                    evt = item.get("event", {})
                    if (
                        evt.get("type") == "build_ended"
                        and evt.get("details", {}).get("buildStatus") == "succeeded"
                    ):
                        print("buildId:", evt.get("details", {}).get("buildId"))
                        break
            return 0
        if status in ("failed", "error", "cancelled", "build_failed"):
            print("Deploy failed with status:", status)
            # print events for debugging
            ev = requests.get(
                f"https://api.render.com/v1/services/{args.service}/events",
                headers={"Authorization": f"Bearer {args.api_key}"},
                timeout=30,
            )
            if ev.status_code == 200:
                print(json.dumps(ev.json()[:20], indent=2)[:4000])
            return 2
        time.sleep(5)
    print("Timeout waiting for deploy to finish")
    return 3


if __name__ == "__main__":
    sys.exit(main())
