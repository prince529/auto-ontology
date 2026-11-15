#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Non-model checks for the loopback profile. Does not call a model endpoint
# and does not print passwords or API keys.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGIN="${APP_URL:-http://127.0.0.1:3000}"
DOCKER="${DOCKER:-docker}"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$ROOT/runtime/admin-password" && -f "$ROOT/runtime/frontend.env" ]] || fail "admin credentials missing"

echo "== published ports =="
ports="$("$DOCKER" ps --filter name=ao-secure- --format '{{.Names}} {{.Ports}}')"
echo "$ports"
if echo "$ports" | grep -E '0\.0\.0\.0:|\[::\]:' >/dev/null; then
  fail "a container publishes a port on all interfaces"
fi
if echo "$ports" | grep -E ':(5432|3001|3002|5050)->' >/dev/null; then
  fail "database, backend, ingestion, or pgAdmin is published"
fi
echo "$ports" | grep -q '127.0.0.1:3000->3000' || fail "frontend is not bound to 127.0.0.1:3000"

echo "== auth =="
python3 "$ROOT/scripts/smoke_http.py" "$ROOT" "$ORIGIN" auth

echo "== catalog wait =="

deadline=$((SECONDS + 180))
catalog=""
while (( SECONDS < deadline )); do
  catalog="$("$DOCKER" exec ao-secure-postgres \
    psql -v ON_ERROR_STOP=1 -U auto_ontology -d auto_ontology -Atc \
    "SELECT (SELECT count(*) FROM catalog_database), (SELECT count(*) FROM catalog_schema), (SELECT count(*) FROM catalog_table), (SELECT count(*) FROM catalog_column), (SELECT count(*) FROM term);" \
    2>/dev/null || true)"
  tables="${catalog##*|} "
  # format is db|schema|table|column|term
  table_count="$(echo "$catalog" | awk -F'|' '{print $3}')"
  if [[ -n "$table_count" && "$table_count" != "0" ]]; then
    break
  fi
  sleep 5
done
echo "catalog counts (db|schema|table|column|term): ${catalog:-none}"
table_count="$(echo "$catalog" | awk -F'|' '{print $3}')"
[[ -n "$table_count" && "$table_count" != "0" ]] || fail "Pagila catalog was not ingested"

python3 "$ROOT/scripts/smoke_http.py" "$ROOT" "$ORIGIN" catalog

echo "== sample rows, vector extension, model status =="
films="$("$DOCKER" exec ao-secure-postgres \
  psql -v ON_ERROR_STOP=1 -U auto_ontology -d pagila -Atc 'SELECT count(*) FROM public.film;')"
echo "pagila.public.film rows: $films"
[[ "$films" -gt 0 ]] || fail "pagila film table is empty"

available="$("$DOCKER" exec ao-secure-postgres \
  psql -v ON_ERROR_STOP=1 -U auto_ontology -d auto_ontology -Atc \
  "SELECT count(*) FROM pg_available_extensions WHERE name = 'vector';")"
[[ "$available" == "1" ]] || fail "pgvector is not available in this Postgres image"
"$DOCKER" exec ao-secure-postgres \
  psql -v ON_ERROR_STOP=1 -U auto_ontology -d auto_ontology -c \
  "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null
vector="$("$DOCKER" exec ao-secure-postgres \
  psql -v ON_ERROR_STOP=1 -U auto_ontology -d auto_ontology -Atc \
  "SELECT extversion FROM pg_extension WHERE extname = 'vector';")"
echo "pgvector extension version: ${vector:-missing}"
[[ -n "$vector" ]] || fail "CREATE EXTENSION vector failed"

term_count="$(echo "$catalog" | awk -F'|' '{print $5}')"
echo "ontology terms: ${term_count:-unknown}"
if [[ "${term_count:-0}" != "0" ]]; then
  echo "NOTE: terms exist. This smoke test does not prove a model-backed compile."
else
  echo "MODEL STEPS AWAITING KEY: semantic terms are empty. Compilation stays off until the NVIDIA key is injected and Settings → Semantic Compilation is enabled."
fi

echo "== internal health =="
"$DOCKER" exec ao-secure-backend python -c "import urllib.request; print('backend', urllib.request.urlopen('http://127.0.0.1:3001/api/health', timeout=5).status)"
"$DOCKER" exec ao-secure-ingestion python -c "import urllib.request; print('ingestion', urllib.request.urlopen('http://127.0.0.1:3002/health', timeout=5).status)"

echo "SMOKE OK"
