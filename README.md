# workflows

Reusable GitHub Actions workflows for the repositories of
[klconsultancy](https://github.com/klconsultancy). A repository calls one with a short
workflow of its own; the logic, the pinned actions and the permissions live here, once.

| Workflow | What it does |
|---|---|
| [`claude-review.yml`](.github/workflows/claude-review.yml) | Claude reviews every pull request against the repository's own `CLAUDE.md` / `AGENTS.md` |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | A pull request's title is a Conventional Commit, the squash commit's message |

## Claude review

On every pull request that is opened, updated, reopened or marked ready, Claude reviews the
change with the [`code-review`](https://github.com/anthropics/claude-code) plugin of
[`claude-code-action`](https://github.com/anthropics/claude-code-action):

- It reviews against the **calling repository's rules**: its `CLAUDE.md`, and the
  `AGENTS.md` that one points to. This workflow stays generic.
- It posts **inline comments**, or one summary comment when it finds nothing. It may also
  skip a pull request it judges trivial, such as a one-line workflow change: then the
  check is green without a comment.
- It **never approves**. A person reads the comments and merges.
- A new push **cancels** the review still running for the same pull request.

Skipped: drafts, pull requests opened by bots (Renovate, release-please; the action refuses
bot actors anyway) and pull requests from forks (GitHub withholds the secret from those).

### Inputs

| Input | Default | What it does |
|---|---|---|
| `max-turns` | `40` | Cap on Claude's turns per review. |
| `timeout-minutes` | `20` | Cap on the job's run time. |
| `guidelines` | `""` | More guideline files to review against, space-separated paths without quotes (e.g. `docs/design/README.md`). `CLAUDE.md` is always read; a file it only links to may not be. |
| `show-full-output` | `false` | Prints Claude's full transcript, tool results included, in the job log, to see what a review read and why. Private repositories only, and only for a while: the log holds whatever Claude read. |

### Once per organization

1. Install the [Claude GitHub App](https://github.com/apps/claude) on all repositories.
2. Run `claude setup-token` and store the token as the organization Actions secret
   `CLAUDE_CODE_OAUTH_TOKEN`. Reviews then run on that Claude subscription. If the
   GitHub plan does not share organization secrets with private repositories, set the
   secret on those repositories instead.

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
    name: Review
    permissions:
      contents: read
      pull-requests: read
      issues: read
      id-token: write # the action authenticates as the Claude GitHub App
    uses: klconsultancy/workflows/.github/workflows/claude-review.yml@<sha> # main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

- Pin `<sha>` to a commit on `main` here. Renovate (`helpers:pinGitHubActionDigests`)
  keeps the pin current.
- The job's permissions are the most the reusable workflow gets: keep them as above.
- Pass the secret by name, not with `secrets: inherit`, so the repository hands over only
  this one.
- Give the repository a `CLAUDE.md` with its rules: the review is only as specific as that.

| Input | Default | Meaning |
|---|---|---|
| `max-turns` | 40 | Cap on Claude's turns per review |
| `timeout-minutes` | 20 | Cap on the job's run time |

```yaml
    with:
      max-turns: 60
```

## PR title

Checks the pull request's title with
[`action-semantic-pull-request`](https://github.com/amannn/action-semantic-pull-request), so
the squash commit is a Conventional Commit. It runs on `pull_request`, not
`pull_request_target`: it only reads the title, which a read-only token can, and the pull
request that adds the caller gets the check too.

Add `.github/workflows/pr-title.yml`:

```yaml
name: PR title

on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

permissions: {}

jobs:
  title:
    name: PR title
    permissions:
      pull-requests: read
    uses: klconsultancy/workflows/.github/workflows/pr-title.yml@<sha> # main
```

The required status check in the repository's ruleset is **`PR title / Conventional commit
title`**: a job from a reusable workflow is named `<caller job> / <its own job>`.

## Changing a workflow here

Every change goes through a pull request. Pin actions to a full commit SHA with the version
in a comment, keep `permissions` minimal and `persist-credentials: false`, and check the
file with [actionlint](https://github.com/rhysd/actionlint) and
[zizmor](https://github.com/zizmorcore/zizmor). Callers only pick a change up when their
pin moves.
