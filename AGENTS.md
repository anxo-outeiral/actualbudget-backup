# AGENTS.md

Guidance for OpenCode sessions working in this repo.

## What this is

Docker image that backs up [Actual Budget](https://actualbudget.org) budgets via `@actual-app/api` and uploads them to remote storage via [rclone](https://rclone.org). Scheduled with `supercronic`. No application framework, no build system, no tests.

This repo is a fork of `rodriguestiago0/actualbudget-backup`. The CI workflow (`.github/workflows/docker-image.yml`) still publishes to the upstream Docker Hub namespace `rodriguestiago0/actualbudget-backup`, triggered on GitHub release publish. Changing the publish target means editing both the workflow `images:` field and `compose.yaml`.

## Layout

- `Dockerfile` — base `rclone/rclone:sha-9ee9d0a` (pinned by SHA; a version tag line is commented out below it). Installs `nodejs npm` + shell tools including `7zip` and `tzdata`. Copies `scripts/*` flat into `/app/`. ENTRYPOINT `/app/entrypoint.sh`.
- `scripts/entrypoint.sh` — `init_env` → `check_rclone_connection all` → configure timezone/cron → run `supercronic` in foreground. Special args: `backup` runs `backup.sh` once and exits; `rclone ...` is a passthrough to the rclone binary.
- `scripts/backup.sh` — sources `includes.sh`; flow is `clear_dir → backup (download) → upload → clear_dir → clear_history`. Exits 1 if a generated archive is missing/empty. Uses `check_rclone_connection any` (continues if some remotes fail, exits if all fail).
- `scripts/includes.sh` — env resolution, rclone connection checks, multi-remote/multi-sync-id list builders. All env handling lives here.
- `scripts/download-actual-budget.js` — Node script using `@actual-app/api`. Parses argv with `minimist`. Called from `backup.sh` with explicit flags (not env vars). Creates archives via `7z` (supports `zip` and `7z` formats with optional password).
- `docs/` — user-facing docs (getting started, multiple remotes/sync-ids, manual trigger, E2E encryption). `README.md` is the canonical reference for env vars.
- `compose.yaml` — example runtime config; the rclone volume `actualbudget-rclone-data` is `external: true` and must be created/configured out of band.

## How to run / verify

There is no lint, typecheck, or test step. Verification is the Docker build + a manual backup run:

```shell
docker build -t actualbudget-backup:dev .
# one-shot backup (requires real env + configured rclone volume)
docker run --rm -it \
  -e ACTUAL_BUDGET_URL=... -e ACTUAL_BUDGET_PASSWORD=... -e ACTUAL_BUDGET_SYNC_ID=... \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  actualbudget-backup:dev backup
```

`backup` arg = run once and exit. No arg = start scheduled `supercronic` loop.

## Gotchas

- **`minimist` is not declared anywhere.** `download-actual-budget.js` does `require('minimist')` at the top. It is not installed by the Dockerfile and there is no `package.json`. It only works because `npm install --prefix /app @actual-app/api` (run at container start in `backup.sh`) happens to pull it transitively. If you change the install path, the API version, or add a `package.json`, verify `minimist` resolves under `NODE_PATH=/app/node_modules` or install it explicitly.
- **`@actual-app/api` is installed at runtime**, not build time. `backup.sh` checks for `/app/node_modules/@actual-app/api` and runs `npm install --prefix /app "@actual-app/api@$API_VERSION" --unsafe-perm` if missing. `ACTUAL_API_VERSION` defaults to `latest`. The image is not self-contained until first backup run.
- **Env resolution priority** (`get_env` in `includes.sh`): real env var → `<VAR>_FILE` secret → `DOTENV_<VAR>_FILE` (from `.env`) → `DOTENV_<VAR>` (from `.env`). `.env` values are namespaced with `DOTENV_` and never override real env vars.
- **Multiple remotes / sync-ids** use zero-indexed env vars: `RCLONE_REMOTE_NAME_0` + `RCLONE_REMOTE_DIR_0`, `ACTUAL_BUDGET_SYNC_ID_0`, `ACTUAL_BUDGET_E2E_PASSWORD_0`, etc. The non-indexed `ACTUAL_BUDGET_SYNC_ID` / `RCLONE_REMOTE_NAME` / `RCLONE_REMOTE_DIR` are aliased to index `_0`. Lists stop at the first empty index.
- **`RCLONE_GLOBAL_FLAG` must not change rclone output** (e.g. `-P`); `clear_history` parses `rclone lsf` output line-by-line, so progress flags corrupt deletion.
- **Backup archive naming**: `backup.<syncId>.<NOW>.<ext>` where `NOW = date +<BACKUP_FILE_DATE_FORMAT>` and `<ext>` is `zip`, `7z`, or `tar` (when `ZIP_ENABLE=FALSE`). `BACKUP_FILE_SUFFIX` overrides `BACKUP_FILE_DATE` + `BACKUP_FILE_DATE_SUFFIX`; `/` is stripped from the format.
- **`.dockerignore` excludes `README.md`, `LICENSE`, `docker-compose*`, `compose*`, `Dockerfile*`, `.env`, `.git`** from the build context. Only `scripts/*` actually gets copied into the image.

## Style

`.editorconfig`: 2-space indent, LF, trim trailing whitespace; **4-space indent for `*.sh`**; `.md` keeps trailing whitespace. Match existing shell style (functions, `color` helper from `includes.sh`, `local` vars).