#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Load the in-repo Pagila sample into its own database. Runs once, from the
# Postgres entrypoint, before the server is marked healthy. The catalog
# database (POSTGRES_DB) is left for Alembic and Prisma.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
SELECT 'CREATE DATABASE pagila'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pagila')\gexec
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname pagila -f /sample/pagila.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname pagila -f /sample/pagila_analytics.sql
