"""Save a full-resolution PNG of the dashboard to docs/dashboard.png.

Uses a Metabase public link (only reachable on 127.0.0.1) and headless Microsoft Edge.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
MB = "http://127.0.0.1:3000"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
NAME = "Customer Retention & Revenue Health"


def main():
    creds = json.loads((ROOT / "tools" / "metabase-admin.local.json").read_text(encoding="utf-8"))
    s = requests.Session()
    r = s.post(f"{MB}/api/session", json={"username": creds["email"], "password": creds["password"]})
    r.raise_for_status()
    s.headers["X-Metabase-Session"] = r.json()["id"]
    s.put(f"{MB}/api/setting/enable-public-sharing", json={"value": True}).raise_for_status()
    dash = max((d for d in s.get(f"{MB}/api/dashboard").json() if d["name"] == NAME), key=lambda d: d["id"])
    uuid = s.post(f"{MB}/api/dashboard/{dash['id']}/public_link").json()["uuid"]
    url = f"{MB}/public/dashboard/{uuid}"

    out = ROOT / "docs" / "dashboard.png"
    out.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=Path.home() / "AppData" / "Local" / "Temp") as profile:
        subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}",
                        "--window-size=1440,2420", "--virtual-time-budget=25000",
                        f"--screenshot={out}", url], check=True, capture_output=True, timeout=180)
    print(out, out.stat().st_size)


if __name__ == "__main__":
    sys.exit(main())
