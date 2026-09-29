# This repo is fake — and that's the point

Every commit to [`log.md`](./log.md) is generated automatically by a scheduled
worker. It writes random Lorem Ipsum text into that file,
roughly on and off during Sydney/Melbourne business hours on weekdays.
No commit to `log.md` represents real work, thought, or effort.

**Why:** GitHub's contribution graph gets treated as a proxy for
"how much someone codes" or "how hard someone works." It isn't. It measures
commit *frequency*, not value, quality, or even whether a human wrote the
code. This repo is a small, honest demonstration of that — a green square
that means nothing, made by a script, so nobody mistakes it for something
it isn't.

If you found this via a contribution graph: the graph lied, or at least
told you a lot less than it looked like it was telling you. Go check the
commit messages — they say so too.

## The rest of the repo is real

The worker is a small PowerShell application deployed with Docker Compose.
One container handles scheduling and GitHub API requests. No Azure account,
database, incoming ports, or local Git checkout inside the container is needed.
GitHub remains the source of truth for the log.

The joke is `log.md`. The plumbing that generates the joke isn't.

## Quick start

Requires Docker Engine with Compose v2, or Docker Desktop using Linux containers.
The image targets **linux/amd64**. ARM hosts need amd64 emulation; a native ARM
image is not provided. Keep the host running when you want scheduled commits.

1. Create a folder for the deployment. Download or copy these two files from
   [the v2.0.0 release](https://github.com/HPyn/vanity-metrics/releases/tag/v2.0.0)
   into that folder:

   - [compose.yaml](https://github.com/HPyn/vanity-metrics/releases/download/v2.0.0/compose.yaml)
   - [env.example](https://github.com/HPyn/vanity-metrics/releases/download/v2.0.0/env.example)

   Rename `env.example` to `.env`. You do not need to clone the repository or
   install PowerShell on the host.

2. Open `.env` and replace `VANITY_METRICS_IMAGE=vanity-metrics:local` with:

   ```dotenv
   VANITY_METRICS_IMAGE=ghcr.io/hpyn/vanity-metrics:v2.0.0
   ```

   Set `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_BRANCH`, and `GITHUB_PATH` to your
   target. Keep `DRY_RUN=true` while setting up. The image is publicly available;
   downloading it does not require a registry login.

3. In the same deployment folder, create `secrets/github_token.txt`. Leave it
   empty for an offline dry-run.
   For real commits, put a fresh fine-grained GitHub token in that file, with
   access to the target repository and **Contents: read and write** permission.
   Keep the token out of `.env`, Compose YAML, and Git. The target branch and
   `log.md` must already exist.

4. Open a terminal in the deployment folder, download the published image,
   and start the worker:

   ```sh
   docker compose pull worker
   docker compose up -d --no-build
   docker compose logs -f worker
   ```

5. Once the token file contains your token, run the read-only access check:

   ```sh
   docker compose run --rm worker -CheckAccess
   ```

   After it succeeds, set `DRY_RUN=false` in `.env` and apply the change:

   ```sh
   docker compose up -d --no-build --force-recreate worker
   ```

`-CheckAccess` deliberately contacts GitHub even when `DRY_RUN=true`. It verifies
authentication and file reads, not write permission. First test real writes on
a separate branch as described in the [deployment guide](docs/deployment.md).

On Linux, make the secret readable by container UID **10001**. One option is
`chmod 700 secrets` and `chmod 444 secrets/github_token.txt`: the host directory
restricts access while the mounted file is readable inside the container.
Use Windows file permissions to restrict the folder on Windows. Compose mounts
the secret as a file; it does not encrypt the source file on your host.

## Environment settings

Edit these values in `.env`. The downloaded example contains the defaults below,
except `VANITY_METRICS_IMAGE`, which you must change to the published image as
shown in the quick start. Keep the token itself in the secret file.

| Variable | Default / deployment value | What it does |
| --- | --- | --- |
| `VANITY_METRICS_IMAGE` | `ghcr.io/hpyn/vanity-metrics:v2.0.0` | Selects the published version to download and run. |
| `DRY_RUN` | `true` | Logs decisions without contacting GitHub. Set `false` to enable commits. The explicit `-CheckAccess` command still contacts GitHub. |
| `GITHUB_OWNER` | `HPyn` | GitHub user or organization that owns the target repository. |
| `GITHUB_REPO` | `vanity-metrics` | Repository to receive the filler commits. |
| `GITHUB_BRANCH` | `main` | Existing branch to write to; use a separate branch for testing. |
| `GITHUB_PATH` | `log.md` | Existing UTF-8 file to append to, relative to the repository root. |
| `GITHUB_TOKEN_SOURCE` | `./secrets/github_token.txt` | Path to the token file on your Docker host, relative to the deployment folder or absolute. |
| `TIME_ZONE` | `Australia/Sydney` | Time zone used for weekdays and working hours, including daylight saving. |
| `WORK_START_HOUR` | `9` | First allowed local hour, inclusive. Use an integer from 0 to 23. |
| `WORK_END_HOUR` | `17` | Ending local hour, exclusive. Must be greater than the start and at most 24. |
| `INTERVAL_MINUTES` | `30` | How often to consider a commit. Must divide 60 evenly, such as 5, 10, 15, 30, or 60. |
| `COMMIT_PROBABILITY` | `0.4` | Base chance per eligible tick, from 0 to 1. `0.4` means 40%. |
| `BUSY_WEEK_MODULO` | `4` | Divides the ISO week number to select a repeating busy/quiet pattern. Must be at least 2. |
| `BUSY_WEEK_REMAINDER` | `0` | Remainder that identifies a busy week. With the defaults, weeks 4, 8, 12, etc. are busy. |
| `BUSY_WEEK_MULTIPLIER` | `2.5` | Multiplies the base probability during busy weeks: 40% becomes 100%. |
| `QUIET_WEEK_REMAINDER` | `2` | Remainder that identifies a quiet week. With the defaults, weeks 2, 6, 10, etc. are quiet. |
| `QUIET_WEEK_MULTIPLIER` | `0.4` | Multiplies the base probability during quiet weeks: 40% becomes 16%. |

Busy and quiet remainders must be different, nonnegative, and less than
`BUSY_WEEK_MODULO`. Other weeks use the base probability. Multipliers must be
nonnegative; the resulting probability is capped at 100%.

`GITHUB_TOKEN_FILE` is set by `compose.yaml` to `/run/secrets/github_token`, the
file's location inside the container. Leave it alone for Compose deployments;
change `GITHUB_TOKEN_SOURCE` in `.env` to select a different host file.

After editing `.env`, apply changes with
`docker compose up -d --no-build --force-recreate worker`. To upgrade to a later
published version, update `VANITY_METRICS_IMAGE`, run `docker compose pull worker`,
then recreate the worker. Stop it with `docker compose down`.

## Behavior and operation

- Every 30 minutes, check Monday–Friday, 09:00–17:00 in `Australia/Sydney`,
  including daylight saving. The default chance of a commit is 40%; busy weeks
  use 100%, and quiet weeks 16%, keyed to ISO week number modulo four.
- Wait for the next interval boundary after startup. Missed ticks are skipped,
  never replayed. Run only one worker against a given target file.
- Dry-run makes no GitHub requests. `docker compose run --rm worker -Once`
  evaluates one tick immediately, still respecting working hours and probability.
- Live mode checks GitHub access at startup. Invalid/expired tokens, denied
  permissions, missing targets, and rate limits appear as explicit errors in
  `docker compose logs worker` and make the container unhealthy. Failed access
  is checked again on the next tick. Docker health status does not send alerts
  or automatically restart an unhealthy container.
- `docker compose ps` shows status; `docker compose down` stops the stack.
  Logs rotate at 5 MB per file, with three files retained.

For token rotation, troubleshooting, source builds, and migration/release steps,
see [deployment.md](docs/deployment.md).

## Development and releases

`src/Worker.psm1` contains configuration, commit decisions, text generation, and
GitHub access. `src/Start-Worker.ps1` runs the scheduler; `src/Test-Health.ps1`
checks the worker heartbeat and last error.

For source builds, see the [deployment guide](docs/deployment.md). Contributors
can run `tests/Run-Tests.ps1` with PowerShell 7.4 or newer and Pester 5.7.1.
`tests/Smoke-Container.ps1` checks a locally built image using a temporary Compose
project and offline dry-run. Deployment from the release files needs neither
PowerShell nor Pester installed on the host.

[CI](.github/workflows/test.yml) tests code and container changes on development
branches and PRs. Publishing a versioned GitHub Release runs the
[release workflow](.github/workflows/release.yml), tests the image, and publishes
it to `ghcr.io/hpyn/vanity-metrics:<release-tag>`. Releases do not automatically
update running hosts. Filler-only commits trigger neither workflow.

The Docker image is published as `v2.0.0`. The former Azure implementation remains
in Git history. Removing its files does not delete any Azure resources.
