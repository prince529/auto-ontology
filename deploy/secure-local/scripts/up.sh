#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Bring up the loopback Auto-Ontology 1.2.0 profile.
# The NVIDIA key is read from a file. It is never printed and never passed
# as a process argument.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEY_FILE="${AUTO_ONTOLOGY_NVIDIA_KEY_FILE:-/workspace/auto-ontology-secrets/nvidia.key}"
APP_URL="${APP_URL:-http://127.0.0.1:3000}"
ADMIN_EMAIL="${AUTO_ONTOLOGY_ADMIN_EMAIL:-ao-admin@example.com}"
DOCKER="${DOCKER:-docker}"

stage_sample() {
  mkdir -p "$ROOT/sample"
  if [[ -f "$ROOT/sample/pagila.sql" && -f "$ROOT/sample/pagila_analytics.sql" ]]; then
    return 0
  fi
  local src
  src="$(cd "$ROOT/../.." && pwd)/dev_tools/fixtures/sql"
  if [[ ! -f "$src/pagila.sql" || ! -f "$src/pagila_analytics.sql" ]]; then
    echo "Pagila SQL is missing from sample/ and from the git checkout." >&2
    echo "Use the handoff archive, which ships sample/pagila.sql." >&2
    exit 1
  fi
  cp "$src/pagila.sql" "$src/pagila_analytics.sql" "$ROOT/sample/"
  chmod a-x "$ROOT/sample/pagila.sql" "$ROOT/sample/pagila_analytics.sql" || true
}

stage_sample
chmod 755 "$ROOT/sample/init-pagila.sh"

python3 "$ROOT/scripts/render-env.py" \
  --root "$ROOT" \
  --key-file "$KEY_FILE" \
  --app-url "$APP_URL" \
  --admin-email "$ADMIN_EMAIL"

echo "Ensuring published images are present (pull, or load images/*.tar)..."
missing=0
for image in \
  "pgvector/pgvector:pg17" \
  "nvcr.io/nvidia/auto-ontology:1.2.0" \
  "nvcr.io/nvidia/auto-ontology-frontend:1.2.0"
do
  if ! "$DOCKER" image inspect "$image" >/dev/null 2>&1; then
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  tar_path=""
  for candidate in \
    "$ROOT/images/auto-ontology-1.2.0-images.tar" \
    "$ROOT/auto-ontology-1.2.0-images.tar"
  do
    if [[ -f "$candidate" ]]; then
      tar_path="$candidate"
      break
    fi
  done
  if [[ -n "$tar_path" ]]; then
    echo "Loading images from $tar_path"
    "$DOCKER" load -i "$tar_path"
  else
    "$DOCKER" pull pgvector/pgvector:pg17@sha256:b513c48566e4777cd3370451400000c78eda6a08131d68f4c31d4a76f27bd8fd
    "$DOCKER" pull nvcr.io/nvidia/auto-ontology:1.2.0@sha256:8348e54e2d733b25dbc17a19172be6c1e3b128c84296da8b465ddcab8d250e3e
    "$DOCKER" pull nvcr.io/nvidia/auto-ontology-frontend:1.2.0@sha256:df3562b159faa86c624d0a6c1a25321a4ce5398a5a29e76ebc4a5f125623a95b
  fi
fi

"$DOCKER" compose -f "$ROOT/docker-compose.yml" up -d --wait

echo
echo "TEMPORARY loopback deployment is up."
echo "Web origin: ${APP_URL}  (published only on 127.0.0.1:3000)"
echo "Admin email: see runtime/frontend.env (AUTO_ONTOLOGY_ADMIN_EMAIL)."
echo "Admin password file: ${ROOT}/runtime/admin-password (mode 600, not printed)."
echo "Postgres, backend :3001, ingestion :3002, and pgAdmin are not published."
echo "Ontology generation, embedding search, and question answering stay"
echo "blocked until AUTO_ONTOLOGY_NVIDIA_KEY_FILE is present and up.sh is re-run."
echo "After the key is injected, sign in and enable Settings → Semantic Compilation."
