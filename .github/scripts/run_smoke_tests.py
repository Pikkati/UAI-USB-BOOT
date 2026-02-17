#!/usr/bin/env python3
"""Simple smoke tests: health and license validate.

Usage: python run_smoke_tests.py --base-url https://uai-license-api.onrender.com

Exits 0 on success, non-zero otherwise.
"""

import argparse
import sys

import requests


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", required=True)
    args = p.parse_args()

    health = f"{args.base_url.rstrip('/')}/health"
    val = f"{args.base_url.rstrip('/')}/api/v1/license/validate"

    try:
        r = requests.get(health, timeout=10)
        print("health HTTP", r.status_code, r.text)
        if r.status_code != 200:
            print("health check failed")
            return 2
    except Exception as e:
        print("health error", e)
        return 3

    # simple validation test with sample payload
    payload = {"license_key": "UAI-PRO-SAR57T4A-528F"}
    try:
        r = requests.post(val, json=payload, timeout=10)
        print("validate HTTP", r.status_code, r.text[:500])
        # allow non-2xx if service returns structured error; treat 400/401 as failure
        if r.status_code >= 400:
            print("license validate returned non-2xx")
            return 4
    except Exception as e:
        print("validate error", e)
        return 5

    print("Smoke tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
