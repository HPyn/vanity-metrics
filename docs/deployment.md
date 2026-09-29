# Docker deployment and migration

## Source builds and published images

The default Compose configuration builds the checkout with
`docker compose up -d --build`. It runs PowerShell 7.6.6 on Ubuntu 24.04 as
UID/GID 10001, with a read-only root filesystem and temporary writable directory.
There are no exposed ports or persistent application volumes.

After a release has been published successfully, you can deploy with just
`compose.yaml`, `.env`, and the secret file. Set this in `.env`:

```dotenv
VANITY_METRICS_IMAGE=ghcr.io/hpyn/vanity-metrics:v2.0.0
```

Then use the published image:

```sh
docker compose pull worker
docker compose up -d --no-build
```

No floating `latest` tag is published. Use the image digest when an immutable
deployment reference is required. To upgrade or roll back a Docker release,
change the version, pull, and recreate the worker. Do not build locally under a
published release tag.

The owner must make the GHCR package public for anonymous pulls, or users must
authenticate to GHCR with package-read access. Registry login is separate from
the worker token. Publishing uses the workflow's built-in GitHub token with
`packages: write`, not the worker's personal access token.

Linux amd64 is supported. Docker Desktop must use Linux containers. ARM hosts
require amd64 emulation and are not natively tested. This is a Docker Compose
deployment for one host, not a Docker Swarm stack.

## Settings

Copy `.env.example` to `.env`. Direct PowerShell runs need equivalent environment
variables; they do not automatically read `.env`.

| Setting | Default | Meaning |
| --- | --- | --- |
| `DRY_RUN` | `true` | Make decisions without GitHub requests; `true` or `false`. |
| `GITHUB_OWNER` | `HPyn` | Repository owner. |
| `GITHUB_REPO` | `vanity-metrics` | Repository name. |
| `GITHUB_BRANCH` | `main` | Existing target branch. |
| `GITHUB_PATH` | `log.md` | Existing UTF-8 file relative to repository root. |
| `GITHUB_TOKEN_SOURCE` | `./secrets/github_token.txt` | Host secret file mounted by Compose. |
| `GITHUB_TOKEN_FILE` | `/run/secrets/github_token` | Container path; fixed in Compose. Override for direct PowerShell runs. |
| `TIME_ZONE` | `Australia/Sydney` | Installed time-zone identifier; automatic daylight saving. |
| `WORK_START_HOUR` | `9` | Inclusive starting hour, 0–23. |
| `WORK_END_HOUR` | `17` | Exclusive ending hour, 1–24, greater than start; no overnight window. |
| `INTERVAL_MINUTES` | `30` | Positive divisor of 60: 1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60. |
| `COMMIT_PROBABILITY` | `0.4` | Base probability from 0 to 1. |
| `BUSY_WEEK_MODULO` | `4` | ISO week number modulo this integer, at least 2. |
| `BUSY_WEEK_REMAINDER` | `0` | Remainder identifying busy weeks. |
| `BUSY_WEEK_MULTIPLIER` | `2.5` | Nonnegative busy-week multiplier. |
| `QUIET_WEEK_REMAINDER` | `2` | Distinct remainder identifying quiet weeks. |
| `QUIET_WEEK_MULTIPLIER` | `0.4` | Nonnegative quiet-week multiplier. |
| `VANITY_METRICS_IMAGE` | `vanity-metrics:local` | Local build name or published image. |

Remainders must be smaller than the modulo. Probabilities are capped at one after
multiplication. Numbers use decimal points regardless of host locale.

Ticks align to UTC interval boundaries, then evaluate weekdays and hours in the
configured zone. For Sydney's default interval this is every hour and half hour.
A restart waits for the next boundary. There is no catch-up queue, public-holiday
calendar, or distributed locking. Run one instance per target.

## Tokens and troubleshooting

Use a fine-grained GitHub token scoped to the target repository with
**Contents: read and write**. Organization approval and branch rules may also
apply. Workflow-management permission is unnecessary for writing `log.md`.

Save only the token in `secrets/github_token.txt`; avoid shell-history exposure.
The file must be readable by UID 10001 inside the container. Restrict its host
folder's permissions; see the README for a Linux example. Secret files and
`.env` are ignored by Git and excluded from the Docker build context.

The read-only check deliberately contacts GitHub even during dry-run:

```sh
docker compose run --rm worker -CheckAccess
```

To rotate an expired token, replace the secret file and recreate the worker:

```sh
docker compose up -d --force-recreate worker
```

Recreating handles editors that replace a file rather than update its existing
inode. The worker also re-reads the token on every API request.

| Symptom | Action |
| --- | --- |
| HTTP 401 | Replace an invalid, expired, or revoked token. |
| HTTP 403 | Check Contents permission, organization authorization, and branch rules. |
| HTTP 404 | Check repository access and that the branch/file already exists. |
| Rate-limit error | This tick is skipped; access is checked next interval. |
| Cannot read token | Check the source path and permissions for UID 10001. |
| Invalid configuration | Correct the named setting and recreate the container. |
| No commits, healthy | Check dry-run, weekday/hour, and probability skip messages. |
| File size error | Archive/rotate the log manually; inline Contents reads require a file below 1 MB. |

Use `docker compose ps` and `docker compose logs --tail=100 worker`. An API
failure leaves the worker unhealthy until a successful access check on a later
tick. Health probes also detect a missing or stale heartbeat. Docker restarts
exited containers under `unless-stopped`, but does not restart an unhealthy
container or send alerts. Use host monitoring if you need notifications.

Transient reads get at most three attempts. A confirmed write conflict causes
one refetch/retry. Write timeouts and server errors are not retried because
GitHub may already have accepted the commit. Requests have a 30-second timeout;
shutdown waits for the current request without starting another retry.

## Validate real writes

1. Create a test branch from the repository so `log.md` already exists there.
2. Set `GITHUB_BRANCH` to that branch; keep `DRY_RUN=true` while checking access.
3. Set `DRY_RUN=false`. For one predictable weekday test, temporarily set hours
   to `0` and `24`, probability to `1`, and both multipliers to `1`.
4. Run `docker compose run --rm worker -Once`. Inspect the real filler commit
   on the selected branch to confirm its content and identity.
5. Restore the intended schedule/probability, select `main`, and start with
   `docker compose up -d --force-recreate`.

Stop any scheduled worker before a one-shot test to the same file. `-Once` still
skips weekends; there is no hidden force-write bypass. The read-only access check
does not prove write permission; this real commit does.

## Azure retirement and release procedure

The owner is deleting Azure manually. This code does not delete cloud resources;
the removed Azure workflow cannot run from the merged Docker version. Historical
Azure code remains in Git, without claiming it is a verified working deployment.

- Remove `rg-vanity-metrics` manually and verify no unwanted resources remain.
- After retirement, remove unused Azure OIDC configuration and repository secrets
  (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and
  `FUNCTION_GITHUB_TOKEN`) if no other workflows use them.
- Develop on `codex/docker-refactor` and review through a PR to `main`. Preserve
  unrelated local edits on `dev`.
- Optionally annotate a tested feature commit with `v2.0.0-rc.1` and publish a
  GitHub prerelease. The workflow tests and publishes the candidate image.
- After tests and the real write check pass, merge the PR, annotate the merge
  commit with `v2.0.0`, and publish a GitHub Release using the prepared notes.
  Stable release commits must belong to `main` history. Wait for the image
  publishing workflow before deploying. Do not move published tags.
- Merge `origin/main` into shared `dev`, preserving local edits first. Delete
  the feature branch when it is no longer needed.

See [release notes](release-notes-v2.0.0.md). Future fixes use `v2.0.1`; compatible
features use `v2.1.0`. Filler-only commits trigger neither builds nor releases.
