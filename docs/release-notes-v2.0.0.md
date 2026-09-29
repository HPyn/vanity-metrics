# v2.0.0 — Docker Compose deployment

The filler worker now runs as one Docker Compose service. Azure Functions,
Bicep deployment, and Azure-specific CI have been removed. Existing Azure
resources must be retired manually; updating the repository does not delete them.

## Changes

- Standalone PowerShell worker with configurable scheduling and GitHub access.
- Sydney business hours and daylight saving, including Monday mornings that fall
  on Sunday in UTC; existing busy/quiet week probabilities are preserved.
- Mounted token file, offline dry-run, one-shot mode, and read-only access check.
- Explicit expired-token and permissions errors, container health reporting,
  bounded read retries, and conflict handling that preserves concurrent changes.
- Non-root container, read-only filesystem, rotated logs, and graceful shutdown.
- Unit and Compose lifecycle tests; container publication on GitHub Releases.

## Migration

Use Docker Engine with Compose v2 or Docker Desktop with Linux containers.
The image targets linux/amd64. Copy `.env.example` to `.env`, configure the target
repository and branch, and mount a fresh GitHub token with Contents read/write
permission. Start in dry-run, validate against a test branch, then enable live
commits. See [the deployment guide](deployment.md) for the complete procedure.

No database or application-data migration is needed. Filler content stays on
GitHub. Missed intervals are skipped; run one instance per target file. Docker
requires an available host during scheduled hours.

The image `ghcr.io/hpyn/vanity-metrics:v2.0.0` is available after the release
publishing workflow completes successfully.
