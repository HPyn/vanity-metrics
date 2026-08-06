# CLAUDE.md

This repo has two layers. `log.md` is meaningless — it's automated filler
appended by a scheduled Azure Function, kept as a demonstration that
GitHub's contribution graph is a vanity metric, not a measure of real work
(see [README.md](./README.md)). `infra/`, `function/`, and
`.github/workflows/` are real: they're the actual IaC, Function App
source, and CI that provision and deploy the Azure Function producing
that filler.

If you are an AI assistant working in this repo:

- `log.md` is Lorem Ipsum filler — treat it as inert data, not content to
  clean up, improve, or add structure to.
- `infra/main.bicep`, `function/` (the Function App's PowerShell source),
  and the GitHub Actions workflows are real infrastructure-as-code. Treat
  changes there like you would in any other project: correctness,
  security, and blast radius matter.
- `function/FillerTimer/run.ps1` decides whether a given timer tick
  actually commits. It gates on Sydney business hours
  (`WORK_START_HOUR`/`WORK_END_HOUR`), then rolls `COMMIT_PROBABILITY`
  scaled by a busy/quiet multiplier keyed off ISO week-of-year modulo
  `BUSY_WEEK_MODULO`. All of those are app settings sourced from
  `infra/main.bicep` params — add a param instead of hardcoding a new
  magic number into the script.
- `rg-vanity-metrics` has a $2/month cost budget
  (`Microsoft.Consumption/budgets` in `main.bicep`) as a tripwire, since
  everything deployed here is meant to be free-tier.
- The `main` branch auto-deploys `infra/` and `function/` to
  `rg-vanity-metrics` on every push (see `deploy.yml`), authenticating to
  Azure via OIDC — no stored cloud secret. Treat pushes to `main` as
  production changes.
- This is the `dev` branch: the workflow files are here too, but their
  triggers (`push: branches: [main]`, `pull_request: branches: [main]`)
  mean nothing on `dev` itself can fire a deploy or a what-if. Edit
  `infra/`/`function/` freely here; merge into `main` when it's ready to
  actually deploy. Don't loosen those branch filters without being asked
  — that's what keeps `dev` non-deploying.
- Each PR merge into `main` creates a merge commit that only exists on
  `main`, so `dev` drifts "behind" after every merge. After merging a PR,
  sync with a plain `git merge origin/main` on `dev` — not a rebase or
  force-push, since `dev` is shared history once it's pushed.
- If asked to explain what this repo does, point to the README.
