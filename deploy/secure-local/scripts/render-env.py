#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Write mode-600 env files for the loopback Compose profile.

The NVIDIA API key is read from a file path. It is written into
``runtime/models.env`` and nowhere else. This process does not print it,
and it does not accept the key on the command line.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import stat
import sys
from pathlib import Path

# Confirmed by the coordinator against this key: models list plus a minimal
# chat completion, HTTP 200. Official nvapi built-in for REASONING is
# nvidia/nemotron-3.5-lightning-30b-a3b; that model was not confirmed.
REASONING_MODEL = "nvidia/nemotron-3.5-bolt-e4b"
NON_REASONING_MODEL = "nvidia/nemotron-3.5-bolt-e4b"
EMBED_MODEL = "nvidia/nemotron-3.5-embed-1b"
RERANK_MODEL = "nvidia/nemotron-3.5-rerank-8b"
INTEGRATE = "https://integrate.api.nvidia.com/v1"
RERANK_ENDPOINT = (
    "https://ai.api.nvidia.com/v1/retrieval/nvidia/nemotron-3.5-rerank-8b/reranking"
)


def _quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _write(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "\n".join(lines) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise SystemExit(f"{path} mode is {mode:o}, expected 600")


def _parse(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        values[key] = value
    return values


def _read_key(path: str | None) -> str:
    if not path:
        return ""
    key_path = Path(path)
    if not key_path.is_file():
        print(
            f"NVIDIA key file not found ({key_path}). "
            "Starting without it. Ontology generation, search embeddings, "
            "and question answering stay blocked until the file is present "
            "and this command is run again.",
            file=sys.stderr,
        )
        return ""
    key = key_path.read_text(encoding="utf-8").strip()
    if not key:
        raise SystemExit(f"NVIDIA key file is empty: {key_path}")
    return key


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--key-file", default="")
    parser.add_argument("--app-url", required=True)
    parser.add_argument("--admin-email", required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    runtime = root / "runtime"
    db_path = runtime / "db.env"
    postgres_path = runtime / "postgres.env"
    frontend_path = runtime / "frontend.env"
    models_path = runtime / "models.env"
    admin_password_path = runtime / "admin-password"

    existing_db = _parse(db_path)
    existing_front = _parse(frontend_path)
    created = not db_path.is_file()

    user = existing_db.get("POSTGRES_USER") or "auto_ontology"
    database = existing_db.get("POSTGRES_DATABASE") or "auto_ontology"
    password = existing_db.get("POSTGRES_PASSWORD") or secrets.token_hex(16)
    auth_secret = existing_front.get("AUTH_SECRET") or secrets.token_hex(32)
    admin_password = existing_front.get("AUTO_ONTOLOGY_ADMIN_PASSWORD") or secrets.token_hex(16)
    admin_email = existing_front.get("AUTO_ONTOLOGY_ADMIN_EMAIL") or args.admin_email

    key = _read_key(args.key_file or None)

    _write(
        db_path,
        [
            f"POSTGRES_USER={_quote(user)}",
            f"POSTGRES_PASSWORD={_quote(password)}",
            f"POSTGRES_DATABASE={_quote(database)}",
            'POSTGRES_PORT="5432"',
        ],
    )
    _write(
        postgres_path,
        [
            f"POSTGRES_USER={_quote(user)}",
            f"POSTGRES_PASSWORD={_quote(password)}",
            f"POSTGRES_DB={_quote(database)}",
        ],
    )
    _write(
        frontend_path,
        [
            f"AUTH_SECRET={_quote(auth_secret)}",
            f"APP_URL={_quote(args.app_url)}",
            f"AUTO_ONTOLOGY_ADMIN_EMAIL={_quote(admin_email)}",
            f"AUTO_ONTOLOGY_ADMIN_PASSWORD={_quote(admin_password)}",
            # Audience string only. This profile does not run or publish the MCP server.
            f"AUTO_ONTOLOGY_MCP_PUBLIC_URL={_quote('http://127.0.0.1:3003')}",
        ],
    )
    connection = f"postgresql://{user}:{password}@postgres:5432/pagila"
    # DEFAULT_MODELS_MODEL is intentionally absent. Setting it to the chat
    # model would become the fallback for EMBED_MODEL and RERANK_MODEL.
    _write(
        models_path,
        [
            f"DEFAULT_MODELS_API_KEY={_quote(key)}",
            f"DEFAULT_MODELS_ENDPOINT={_quote(INTEGRATE)}",
            f"REASONING_ENDPOINT={_quote(INTEGRATE)}",
            f"REASONING_MODEL={_quote(REASONING_MODEL)}",
            f"NON_REASONING_ENDPOINT={_quote(INTEGRATE)}",
            f"NON_REASONING_MODEL={_quote(NON_REASONING_MODEL)}",
            f"EMBED_ENDPOINT={_quote(INTEGRATE)}",
            f"EMBED_MODEL={_quote(EMBED_MODEL)}",
            f"RERANK_ENDPOINT={_quote(RERANK_ENDPOINT)}",
            f"RERANK_MODEL={_quote(RERANK_MODEL)}",
            f"CONNECTION_STRINGS={_quote(connection)}",
            'INGESTION_SERVICE_URL="http://ingestion-service:3002"',
        ],
    )
    _write(admin_password_path, [admin_password])

    json.dump(
        {
            "created": created,
            "key_injected": bool(key),
            "admin_email": admin_email,
            "app_url": args.app_url,
            "admin_password_file": str(admin_password_path),
            "reasoning_model": REASONING_MODEL,
            "non_reasoning_model": NON_REASONING_MODEL,
            "embed_model": EMBED_MODEL,
            "rerank_model": RERANK_MODEL,
        },
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
