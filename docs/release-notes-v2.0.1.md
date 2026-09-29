# v2.0.1 — Ready-to-run Compose defaults

The downloaded Compose and environment files now select
`ghcr.io/hpyn/vanity-metrics:v2.0.1` automatically. Users no longer need to replace
the local development image setting before starting the worker.

- Removed the source-build step from the deployment Compose file.
- Made the published image the default in both Compose and the example settings.
- Simplified the README quick start and documented every environment setting.
- Kept an explicit image override for upgrades and local development builds.

Download `compose.yaml` and `env.example` from this release into one folder.
Rename `env.example` to `.env`, configure your repository and token, and run:

```sh
docker compose pull worker
docker compose up -d --no-build
```

The default remains dry-run. See [the deployment guide](deployment.md) before
enabling commits. Existing deployments can select the v2.0.1 image and recreate
the worker. Runtime behavior and the token format are unchanged.
