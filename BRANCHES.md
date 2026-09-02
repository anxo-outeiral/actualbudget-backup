# Branch overview

> Internal fork documentation — never included in upstream PRs. Update when branch state changes.
> Last updated: 2026-09-02

This fork (`anxo-outeiral/actualbudget-backup`) tracks upstream (`rodriguestiago0/actualbudget-backup`). Branches are organized by purpose so each pending proposal to upstream has its own ready branch.

## Branches

| Branch | Role | Contents |
|---|---|---|
| `main` | Base — upstream synced + fork-only files | Everything merged upstream (PR #18) plus `AGENTS.md` and this file |
| `upstream-merged` | Read-only mirror of `upstream/main` | Reference for clean diffs and PR branch bases |
| `pr/fix-multiarch` | Open PR [#20](https://github.com/rodriguestiago0/actualbudget-backup/pull/20) | Multi-arch fix (QEMU + `platforms:`) for `docker-image.yml` |
| `feat/cicd` | Ready for PR when upstream approves option 1 of issue [#19](https://github.com/rodriguestiago0/actualbudget-backup/issues/19) | `ci.yml` (bats tests + build validation, no publish), `test/includes.bats`, multi-arch fix |
| `feat/runtime-features` | Feature pack — split into small PRs when approved | Webhooks (`WEBHOOK_*`), `RETENTION_COUNT`, `BACKUP_ON_START`, `RCLONE_CONFIG_*` env config, `_FILE` rclone secrets, security docs, `test/includes-features.bats` |

## Pending on upstream

- **PR #20** (from `pr/fix-multiarch`): multi-arch fix — awaiting review.
- **Issue #19, option 1** (CI build on merge): awaiting decision. If approved, open PR from `feat/cicd`.
- **Runtime features**: propose in small PRs (webhooks / retention + backup-on-start / rclone env config) once the above land. Source branch: `feat/runtime-features`.

## Conventions

- PRs to upstream are opened from dedicated clean branches (`pr/*`) created off `upstream/main`, excluding fork-only files (`AGENTS.md`, `BRANCHES.md`).
- `feat/*` branches are staging branches off `main`.
- Sync `main` with `upstream/main` via merge — no rebase, no force-push.
- Delete `pr/*` branches after their PRs are merged.

## Known gaps (not yet implemented)

- `backup.sh` functions are not unit-testable without refactor (sourcing it runs the whole backup) — its tests are deferred.
- `@actual-app/api` is cached forever in a live container (`backup.sh` only installs if missing) — schema drift breaks backups after a server upgrade. Workaround: pin `ACTUAL_API_VERSION` and recreate the container on upgrades.
- Remaining features from the vaultwarden-backup/export comparison: Mail SMTP notifications, Ping-style healthchecks, automated restore.
