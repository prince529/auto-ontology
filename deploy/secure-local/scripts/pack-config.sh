#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Build a source-free config archive. It contains Compose, scripts, and the
# Pagila sample SQL. It does not contain runtime secrets or container images.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
OUT="${1:-$ROOT/auto-ontology-1.2.0-secure-local-config.tar.gz}"
stage="$(mktemp -d)"
dest="$stage/auto-ontology-1.2.0-secure-local"
mkdir -p "$dest/scripts" "$dest/sample"

cp "$ROOT/docker-compose.yml" "$ROOT/README.md" "$ROOT/.gitignore" "$dest/"
cp "$ROOT/scripts/up.sh" "$ROOT/scripts/down.sh" "$ROOT/scripts/smoke.sh" \
  "$ROOT/scripts/smoke_http.py" "$ROOT/scripts/render-env.py" \
  "$ROOT/scripts/pack-config.sh" "$dest/scripts/"
cp "$ROOT/sample/init-pagila.sh" "$dest/sample/"
cp "$REPO/dev_tools/fixtures/sql/pagila.sql" \
  "$REPO/dev_tools/fixtures/sql/pagila_analytics.sql" \
  "$dest/sample/"
chmod 755 "$dest/scripts/"*.sh "$dest/scripts/"*.py "$dest/sample/init-pagila.sh"

tar -C "$stage" -czf "$OUT" auto-ontology-1.2.0-secure-local
rm -rf "$stage"
echo "Wrote $OUT"
