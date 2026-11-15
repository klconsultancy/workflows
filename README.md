# workflows

Reusable GitHub Actions workflows for the repositories of klconsultancy.

## Claude review

[`claude-review.yml`](.github/workflows/claude-review.yml) has Claude review every pull
request against the repository's own `CLAUDE.md` / `AGENTS.md`. It posts inline comments,
or one summary comment when it finds nothing. It never approves: a person merges.

Skipped: draft pull requests, pull requests opened by bots (Renovate, release-please) and
pull requests from forks (GitHub withholds the secret from those).

### Once per organization

1. Install the [Claude GitHub App](https://github.com/apps/claude) on all repositories.
2. Run `claude setup-token` and store the token as the organization Actions secret
   `CLAUDE_CODE_OAUTH_TOKEN`. If the plan does not share organization secrets with private
   repositories, set it on those repositories instead.

### In a repository

Add `.github/workflows/claude-review.yml`:

```yaml
name: Claude review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]

permissions: {}

jobs:
  review:
    permissions:
      contents: read
      pull-requests: read
      issues: read
      id-token: write
    uses: klconsultancy/workflows/.github/workflows/claude-review.yml@<sha> # main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Pin `<sha>` to a commit of this repository. Optional inputs: `max-turns` (default 40)
and `timeout-minutes` (default 20).
