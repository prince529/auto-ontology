# Auto-Ontology 1.2.0 loopback profile

临时单机部署，不是生产安装。

This directory runs the published Auto-Ontology 1.2.0 images on one Docker
host. It keeps Better Auth sign-in, loads the Pagila sample, and publishes
only `127.0.0.1:3000`. It does not generate an ontology or answer a question
until an NVIDIA API key is injected from a file on that host.

Production remains the Helm chart `auto-ontology` 1.2.0 from
`https://helm.ngc.nvidia.com/nvidia` (`charts/auto-ontology-1.2.0.tgz`), with
TLS, `appUrl` set to the real origin, pgAdmin left disabled, and secrets
supplied outside git. This host has Docker and no Kubernetes, so Helm is not
the install used here. The root `docker-compose.yml` is the upstream
one-machine file and publishes Postgres, pgAdmin, the backend, and ingestion.
Do not use it for this deployment.

## What is running

| Piece | Image | Published |
| --- | --- | --- |
| Web app and Better Auth | `nvcr.io/nvidia/auto-ontology-frontend:1.2.0` | `127.0.0.1:3000` only |
| FastAPI backend | `nvcr.io/nvidia/auto-ontology:1.2.0` | not published |
| Ingestion worker | same backend image, command `ingestion_service` | not published |
| Postgres 17 + pgvector | `pgvector/pgvector:pg17` | not published |
| pgAdmin | omitted | not published |
| MCP server | not included | not published |

Digests:

- `nvcr.io/nvidia/auto-ontology@sha256:8348e54e2d733b25dbc17a19172be6c1e3b128c84296da8b465ddcab8d250e3e`
- `nvcr.io/nvidia/auto-ontology-frontend@sha256:df3562b159faa86c624d0a6c1a25321a4ce5398a5a29e76ebc4a5f125623a95b`
- `pgvector/pgvector@sha256:b513c48566e4777cd3370451400000c78eda6a08131d68f4c31d4a76f27bd8fd`

Anonymous `docker pull` of these three images was verified. `scripts/up.sh`
pulls them when they are absent, or loads `images/auto-ontology-1.2.0-images.tar`
when that file is next to this directory.

## Sample data

Pagila (MIT, the fixture in `dev_tools/fixtures/sql`) is loaded into database
`pagila` on the same Postgres. `CONNECTION_STRINGS` points at it. This is not
the README quickstart's Wide World Importers database. That seed lives in
`NVIDIA/auto-ontology-eval` and requires cloning another repository onto the
deploy host. Pagila has schemas, foreign keys, views, and rows. It is sample
data, not enterprise data.

The question in the upstream README about a USB flash drive does not apply to
Pagila.

## Bring-up

On the Docker host, from this directory:

```bash
export DOCKER_HOST=tcp://127.0.0.1:2375   # only if the engine is not the local socket
export AUTO_ONTOLOGY_NVIDIA_KEY_FILE=/workspace/auto-ontology-secrets/nvidia.key
export APP_URL=http://127.0.0.1:3000
./scripts/up.sh
./scripts/smoke.sh
```

`APP_URL` must be the exact origin typed in the browser. A mismatch makes
Better Auth reject the session. `ssh -L 3000:127.0.0.1:3000` and then opening
`http://localhost:3000` requires `APP_URL=http://localhost:3000` before the
first `up.sh`. Changing it later is safe: `up.sh` keeps the existing admin
password and auth secret and rewrites `APP_URL`.

The admin password is generated on first run and written to
`runtime/admin-password` (mode 600). It is not printed. The email defaults to
`ao-admin@example.com`. Override `AUTO_ONTOLOGY_ADMIN_EMAIL` before the first
run. Self-service sign-up is disabled.

There is no public preview URL on the build VM. Reach the app through the
loopback port, or through an SSH tunnel to that port. Do not publish
`0.0.0.0:3000`.

`scripts/down.sh` stops the stack and keeps the volume. `docker compose down -v`
deletes Postgres.

## NVIDIA key

The key file is read by `scripts/render-env.py`. The value is written only to
`runtime/models.env` (mode 600), which is mounted into the backend and the
ingestion worker. It is not passed as a process argument, not given to the
frontend container, and not printed. Re-run `up.sh` after the file exists to
inject it without rotating passwords.

Do not commit `runtime/`.

### Model roles

Leave `DEFAULT_MODELS_MODEL` unset. If it is set to the chat model, an unset
`EMBED_MODEL` or `RERANK_MODEL` inherits that chat model and embeddings land
in the wrong space.

| Role | Env | Endpoint | Model | Key status |
| --- | --- | --- | --- | --- |
| Shared key | `DEFAULT_MODELS_API_KEY` | `DEFAULT_MODELS_ENDPOINT=https://integrate.api.nvidia.com/v1` | unset on purpose | Inject from the key file. Per-role `*_API_KEY` vars are unset and fall back to this one. |
| `REASONING` | `REASONING_ENDPOINT`, `REASONING_MODEL` | `https://integrate.api.nvidia.com/v1` | `nvidia/nemotron-3.5-bolt-e4b` | Chat HTTP 200 was confirmed for this model. The code's nvapi built-in is `nvidia/nemotron-3.5-lightning-30b-a3b`, which was not confirmed for this key. |
| `NON_REASONING` | `NON_REASONING_ENDPOINT`, `NON_REASONING_MODEL` | same integrate host | `nvidia/nemotron-3.5-bolt-e4b` | Not separately confirmed. Set to the only verified chat model so entity extraction does not target an untested id. |
| `EMBED` | `EMBED_ENDPOINT`, `EMBED_MODEL` | `https://integrate.api.nvidia.com/v1` | `nvidia/nemotron-3.5-embed-1b` | Not confirmed. Ingest and query must keep this exact pair. Official nvapi built-in. |
| `RERANK` | `RERANK_ENDPOINT`, `RERANK_MODEL` | `https://ai.api.nvidia.com/v1/retrieval/nvidia/nemotron-3.5-rerank-8b/reranking` | `nvidia/nemotron-3.5-rerank-8b` | Not confirmed. This host is not the integrate host. Official nvapi built-in. |

`sk-` keys would select `https://inference-api.nvidia.com/v1` and different
model ids. This profile assumes an `nvapi-` key. A key with a different
prefix still needs the endpoints above overridden only if those calls fail.

KumoRFM is unset, so predictions stay off.

## After the key is injected

1. `./scripts/up.sh` again so the backend and ingestion worker pick up the key.
2. Sign in at `APP_URL`.
3. Settings → Semantic Compilation: turn it on.
4. Wait until that page reports the layer is ready. `GET /api/semantic-compilation/status`
   returns `calculated: false` until a Term exists.
5. Only then ask a question in Chat, and use Search.

Until steps 3–5 succeed against the live model, ontology generation and
question answering are **not** done. Catalog browse of Pagila can succeed
without the key because schema ingest is separate from embedding.

## If containers cannot reach Postgres

`up.sh` on a normal Docker Engine does not change the host firewall. On one
test VM, `iptables-legacy` still had `FORWARD` policy `DROP` and only accepted
the default `docker0` bridge, while the compose network used `ao-secure0`.
Postgres was healthy on its private IP and every other container timed out
connecting to `postgres:5432`. Allowing forwarded traffic from that bridge on
the legacy table fixed it. Check this only if migrate fails with Prisma
`P1001` while `pg_isready` inside the Postgres container succeeds.

## Memory

The target host has about 15 GiB RAM and about 2.6 GiB free, and no GPU.
Models are remote NVIDIA API calls. Postgres is started with `shared_buffers=128MB`
and `max_connections=30`. The backend still spawns one warm chat worker
process; that is upstream behavior and there is no switch to disable it.
Measure `docker stats` after start. If the box is out of memory, free RAM
before adding this stack. Do not add pgAdmin.

## Config archive

`scripts/pack-config.sh /path/to/auto-ontology-1.2.0-secure-local-config.tar.gz`
packs this directory plus the Pagila SQL and omits `runtime/`. The extracted
directory does not need a git checkout.
