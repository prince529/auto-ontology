#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Stop the loopback profile and keep the Postgres volume.
# `docker compose down -v` deletes the catalog and the Pagila sample. Do not
# pass -v unless that data is meant to be discarded.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
"$DOCKER" compose -f "$ROOT/docker-compose.yml" down
