#!/usr/bin/env python3
"""Patch a Render service to use a given image and trigger a deploy.

Usage: python patch_and_deploy_render.py --service <service-id> --api-key <key> --image <image-url>

This script patches `serviceDetails.envSpecificDetails.image` and then POSTs
to /v1/services/{service}/deploys to trigger a deploy.
"""

import argparse
import json
import requests
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--service", required=True)
    p.add_argument("--api-key", required=True)
    p.add_argument("--image", required=True)
    p.add_argument("--docker-cmd", default="python run_production_server.py")
    args = p.parse_args()

    headers = {
        "Authorization": f"Bearer {args.api_key}",
        "Content-Type": "application/json",
    }
    url = f"https://api.render.com/v1/services/{args.service}"

    payload = {
        "serviceDetails": {
            "env": "docker",
            "envSpecificDetails": {
                "image": args.image,
                "dockerCommand": args.docker_cmd,
            },
        }
    }

    print("Patching Render service to set image ->", args.image)
    r = requests.patch(url, headers=headers, json=payload, timeout=30)
    print(r.status_code)
    try:
        print(json.dumps(r.json(), indent=2))
    except Exception:
        print(r.text[:2000])

    if r.status_code not in (200, 202):
        print("Failed to patch service. Exiting.")
        return 2

    # Trigger a deploy (POST without body works)
    deploy_url = f"https://api.render.com/v1/services/{args.service}/deploys"
    print("Triggering deploy...")
    r2 = requests.post(
        deploy_url, headers={"Authorization": f"Bearer {args.api_key}"}, timeout=30
    )
    print("deploy HTTP", r2.status_code)
    try:
        print(json.dumps(r2.json(), indent=2))
    except Exception:
        print(r2.text[:2000])

    if r2.status_code not in (200, 201):
        print("Failed to trigger deploy.")
        return 3

    print("Deploy triggered successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
