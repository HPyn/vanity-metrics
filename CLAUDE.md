# Project guidance

`log.md` is intentionally meaningless automated filler. Treat it as inert data;
do not clean it up, restructure it, or add manual demonstration entries.
See README.md for the project's purpose.

The real application is a PowerShell worker in `src/`, deployed by `compose.yaml`.
The former Azure Function and Bicep infrastructure are preserved in Git history.
Azure resources are removed manually by the owner; repository edits must not
attempt to delete cloud resources.

- Keep schedule and probability controls configurable through environment
  variables, validated by Get-WorkerConfig, and documented in `.env.example`.
- Keep weekday and working-hour checks in the configured local time zone.
  UTC weekdays are not equivalent to Sydney weekdays.
- Dry-run must make no GitHub requests. The explicitly requested -CheckAccess
  mode is read-only and may contact GitHub regardless of DRY_RUN.
- Tokens come from a mounted secret file. Never put secrets in Git, Docker build
  arguments, image layers, logs, or test output. `.env` and `secrets/` are ignored.
- Preserve honest automated-filler commit messages and the existing log content.
- GET requests may retry transient errors. Retry a PUT only after a definite
  409 conflict and a fresh GET; ambiguous network failures must not duplicate writes.
- Run Pester tests and Compose smoke tests for runtime changes. Tests use mocks
  or dry-run and must not write to a real repository by default.
- Filler-only commits must not trigger CI builds or releases. Image publishing
  happens only when a GitHub Release is published. PR validation needs no cloud
  credentials or repository-write token.
- Work on feature branches and merge through PRs. Stable releases use annotated
  vMAJOR.MINOR.PATCH tags from main; candidates use vMAJOR.MINOR.PATCH-rc.N.
  Do not merge or publish a stable release merely to finish a development task.
- After merging into main, synchronize shared dev with a normal merge from
  origin/main, not a rebase or force-push. Preserve unrelated local edits.
