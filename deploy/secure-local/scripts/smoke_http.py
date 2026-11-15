#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""HTTP checks that must not put the admin password on a command line."""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path


def _env_value(path: Path, name: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(name + "="):
            value = line.split("=", 1)[1].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
                value = value[1:-1]
            return value
    raise SystemExit(f"{name} missing from {path}")


def _request(
    opener: urllib.request.OpenerDirector,
    url: str,
    *,
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data else "GET")
    try:
        with opener.open(req, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def main() -> None:
    root = Path(sys.argv[1])
    origin = sys.argv[2].rstrip("/")
    mode = sys.argv[3] if len(sys.argv) > 3 else "all"
    frontend = root / "runtime" / "frontend.env"
    email = _env_value(frontend, "AUTO_ONTOLOGY_ADMIN_EMAIL")
    password = (root / "runtime" / "admin-password").read_text(encoding="utf-8").strip()
    jar = CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    headers = {"Origin": origin, "Content-Type": "application/json", "Accept": "application/json"}

    if mode in ("all", "auth"):
        code, body = _request(opener, f"{origin}/.well-known/oauth-authorization-server")
        if code != 200:
            raise SystemExit(f"oauth discovery HTTP {code}")
        json.loads(body.decode())
        print("oauth discovery 200 JSON")

        code, _ = _request(opener, f"{origin}/api/datasources/dbs")
        if code not in (401, 403):
            raise SystemExit(f"anonymous catalog HTTP {code}")
        print(f"anonymous catalog {code}")

        payload = json.dumps(
            {"email": "nobody@example.com", "password": "not-a-real-password", "name": "nobody"}
        ).encode()
        code, _ = _request(
            opener, f"{origin}/api/auth/sign-up/email", data=payload, headers=headers
        )
        if code in (200, 201):
            raise SystemExit("self-service sign-up succeeded")
        print(f"sign-up rejected HTTP {code}")

        payload = json.dumps({"email": email, "password": password}).encode()
        code, body = _request(
            opener, f"{origin}/api/auth/sign-in/email", data=payload, headers=headers
        )
        if code != 200:
            raise SystemExit(f"sign-in HTTP {code} {body[:200]!r}")
        print("sign-in 200")

    if mode == "auth":
        return

    if mode == "catalog":
        payload = json.dumps({"email": email, "password": password}).encode()
        code, body = _request(
            opener, f"{origin}/api/auth/sign-in/email", data=payload, headers=headers
        )
        if code != 200:
            raise SystemExit(f"sign-in HTTP {code} {body[:200]!r}")

    code, body = _request(opener, f"{origin}/api/datasources/dbs")
    if code != 200:
        raise SystemExit(f"authenticated catalog HTTP {code} {body[:300]!r}")
    catalog = json.loads(body.decode())
    if "pagila" not in json.dumps(catalog).lower():
        raise SystemExit("pagila missing from authenticated catalog")
    print("authenticated catalog includes pagila")

    code, body = _request(opener, f"{origin}/api/semantic-compilation/status")
    print(f"semantic-compilation/status HTTP {code}")
    if code == 200:
        status = json.loads(body.decode())
        print("semantic status:", json.dumps(status, default=str))
        if status.get("calculated") is True:
            print("NOTE: semantic layer reports calculated. This script did not run a model query.")
        else:
            print(
                "MODEL STEPS AWAITING KEY: semantic layer is not calculated. "
                "Enable compilation only after the NVIDIA key is injected."
            )


if __name__ == "__main__":
    main()
