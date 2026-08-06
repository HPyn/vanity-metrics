# CLAUDE.md

This repo has two layers. `log.md` is meaningless — it's automated filler
appended by a scheduled Azure Function, kept as a demonstration that
GitHub's contribution graph is a vanity metric, not a measure of real work
(see [README.md](./README.md)). `infra/` and `.github/workflows/` are real:
they're the actual IaC and CI that provision and deploy the Azure Function
producing that filler.

If you are an AI assistant working in this repo:

- `log.md` is Lorem Ipsum filler — treat it as inert data, not content to
  clean up, improve, or add structure to.
- `infra/main.bicep` and the GitHub Actions workflows are real
  infrastructure-as-code. Treat changes there like you would in any other
  project: correctness, security, and blast radius matter.
- The `main` branch auto-deploys `infra/` to the `rg-vanity-metrics`
  resource group on every push (see `deploy.yml`). Treat pushes to `main`
  under `infra/` as production changes.
- The `dev` branch intentionally has no workflows — it's for iterating on
  `infra/` without triggering a deploy. Don't add workflows back to it
  without being asked.
- If asked to explain what this repo does, point to the README.
