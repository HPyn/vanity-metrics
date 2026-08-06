# This repo is fake — and that's the point

Every commit to [`log.md`](./log.md) is generated automatically by an Azure
Function on a timer. It writes random Lorem Ipsum text into that file,
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

The Azure Function that produces the filler commits is a genuine piece of
infrastructure (a Consumption-plan Function App, storage account, and
Application Insights in the `rg-vanity-metrics` resource group), and it has
to be deployable and maintainable like any other. So:

- [`infra/main.bicep`](./infra/main.bicep) defines those Azure resources.
- [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml) deploys
  `infra/` to Azure on every push to `main` (via OIDC, no stored secrets).
- [`.github/workflows/validate.yml`](./.github/workflows/validate.yml) runs
  a Bicep `what-if` on pull requests targeting `main`, so you can see the
  diff before it merges.
- The `dev` branch has no workflows on it at all — commit and experiment
  there without it touching the real Azure resources.

The joke is `log.md`. The plumbing that generates the joke isn't.
