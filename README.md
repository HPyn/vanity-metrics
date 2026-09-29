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

1. Clone this repository and copy `.env.example` to `.env`.
2. Create `secrets/github_token.txt`. Leave it empty for an offline dry-run.
   For real commits, put a fresh fine-grained GitHub token in that file, with
   access to the target repository and **Contents: read and write** permission.
   Keep the token out of `.env`, Compose YAML, and Git. The target branch and
   `log.md` must already exist.
3. Review the target repository and branch in `.env`. Start with the default
   `DRY_RUN=true`:

   ```sh
   docker compose up -d --build
   docker compose logs -f worker
   ```

4. To enable writes, first run the read-only access check, then set
   `DRY_RUN=false` in `.env` and recreate the worker:

   ```sh
   docker compose run --rm worker -CheckAccess
   docker compose up -d --force-recreate
   ```

`-CheckAccess` deliberately contacts GitHub even when `DRY_RUN=true`. It verifies
authentication and file reads, not write permission. First test real writes on
a separate branch as described in the [deployment guide](docs/deployment.md).

On Linux, make the secret readable by container UID **10001**. One option is
`chmod 700 secrets` and `chmod 444 secrets/github_token.txt`: the host directory
restricts access while the mounted file is readable inside the container.
Use Windows file permissions to restrict the folder on Windows. Compose mounts
the secret as a file; it does not encrypt the source file on your host.

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

For all settings, token rotation, published images, and migration/release steps,
see [deployment.md](docs/deployment.md).

## Development and releases

`src/Worker.psm1` contains configuration, commit decisions, text generation, and
GitHub access. `src/Start-Worker.ps1` runs the scheduler; `src/Test-Health.ps1`
checks the worker heartbeat and last error.

Install the test-only dependency and run tests with PowerShell 7.4 or newer:

```powershell
Save-Module Pester -RequiredVersion 5.7.1 -Path .tools -Force
./tests/Run-Tests.ps1
docker build --platform linux/amd64 -t vanity-metrics:local .
./tests/Smoke-Container.ps1
```

The smoke test uses its own temporary Compose project, an empty token, and
dry-run mode. It never writes to GitHub and removes its test containers afterward.
The runtime has no PowerShell module dependencies.

[CI](.github/workflows/test.yml) tests code and container changes on development
branches and PRs. Publishing a versioned GitHub Release runs the
[release workflow](.github/workflows/release.yml), tests the image, and publishes
it to `ghcr.io/hpyn/vanity-metrics:<release-tag>`. Releases do not automatically
update running hosts. Filler-only commits trigger neither workflow.

The Docker migration is intended for `v2.0.0`; an image is available only after
its release workflow succeeds. The former Azure implementation remains in Git
history. Removing its files does not delete any Azure resources.
