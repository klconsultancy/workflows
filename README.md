# workflows

Reusable GitHub Actions workflows for the repositories of
[klconsultancy](https://github.com/klconsultancy). A repository calls one with a short
workflow of its own; the logic, the pinned actions and the permissions live here, once.

| Workflow | What it does |
|---|---|
| [`claude-review.yml`](.github/workflows/claude-review.yml) | Claude reviews every pull request against the repository's own `CLAUDE.md` / `AGENTS.md` |
| [`pr-title.yml`](.github/workflows/pr-title.yml) | A pull request's title is a Conventional Commit, the squash commit's message |
| [`zizmor.yml`](.github/workflows/zizmor.yml) | zizmor audits the repository's own workflows, at a version pinned here |
| [`python-uv.yml`](.github/workflows/python-uv.yml) | ruff, mypy, pytest (a Python matrix) and a checked build, for a uv project |
| [`home-assistant.yml`](.github/workflows/home-assistant.yml) | hassfest and HACS validation of a Home Assistant custom integration |
| [`shell.yml`](.github/workflows/shell.yml) | shellcheck, `zsh -n`, gitleaks and bats, for scripts and dotfiles |
| [`renovate.yml`](.github/workflows/renovate.yml) | Renovate as a GitHub App, its version pinned once for every repository |

The repository is public, so repositories outside the organization (a personal account's,
private ones too) can call these workflows as well. Each workflow's header holds its caller
and its inputs.

## Claude review

On every pull request that is opened, updated, reopened or marked ready, Claude reviews the
change with [`claude-code-action`](https://github.com/anthropics/claude-code-action) and this
workflow's own prompt:

- It reviews against the **calling repository's rules**: every `CLAUDE.md` and `AGENTS.md`,
  the files they import with `@`, and the `guidelines` input. The rules come from the
  **base branch**: a pull request cannot change the rules it is reviewed against. A change to
  a rules file is itself reviewed, and named in the summary.
- **Every push** is reviewed. After the first review, only what changed since the last
  successful review (changes merged in from the base left out). A force-push or a base merge
  that resolved conflicts gets a full review again.
- It posts **inline comments**, and one **summary comment per push**: the scope, the files
  it read, what it skipped, and the rules that applied. A clean review is one line.
- The check is **red** when Claude ended without a summary: a green check means a review.
  Expect red on a pull request that adds or changes the caller workflow file: the Claude
  GitHub App only grants its token for a caller identical to the default branch's, and it
  compares a reusable workflow the caller takes from its own repository the same way. So a
  pull request here that changes `claude-review.yml` is red too ("Workflow validation
  failed", #9): such a change is tested only after the merge, in a caller.
- It **never approves**. A person reads the comments and merges.
- Its tools are a **strict list**: reading files, inline comments, `gh pr view`, `gh pr diff`
  and `gh pr comment`. Anything else is denied (`--permission-mode default`, not the
  action's auto mode, whose safety review can pass a call no rule allows): a review reads
  untrusted pull request content, so that content must not be able to make it run commands.
- A new push **cancels** the review still running for the same pull request; the next
  review then covers both pushes.

Shell scripts in [`.github/claude-review/`](.github/claude-review) decide the scope and put
the base rules in place before Claude starts; [`test/`](test) holds their tests
(`bats test/`).

Skipped: drafts, pull requests opened by bots (Renovate, release-please; the action refuses
bot actors anyway) and pull requests from forks (GitHub withholds the secret from those).

### Inputs

| Input | Default | What it does |
|---|---|---|
| `model` | `claude-opus-5-5` | The Claude model that reviews. |
| `max-turns` | `40` | Cap on Claude's turns per review. |
| `timeout-minutes` | `20` | Cap on the job's run time. |
| `guidelines` | `""` | More guideline files to review against, space-separated paths without quotes (e.g. `docs/design/README.md`). `CLAUDE.md`, `AGENTS.md` and the files they import with `@` are always read; a file they only link to is not. |
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
      actions: read # find the last successful review
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

Inputs (see the table above) go under `with:`:

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
  merge_group: # only with a merge queue

permissions: {}

jobs:
  title:
    name: PR title
    permissions:
      pull-requests: read
    uses: klconsultancy/workflows/.github/workflows/pr-title.yml@<sha> # main
```

The required status check in the repository's ruleset is **`PR title / Conventional commit
title`**: a job from a reusable workflow is named `<caller job> / <its own job>`. With a
merge queue, a required check must also report on the queue's merge group, so the caller
adds `merge_group`. There the check passes without checking: the group has no title, and the
pull request's title was checked before it entered the queue.

## zizmor

[`zizmor.yml`](.github/workflows/zizmor.yml) audits the calling repository's workflows with
[zizmor](https://github.com/zizmorcore/zizmor), at the version pinned here. Inputs: `paths`
(default `.github/`), `config` (the repository's `.github/zizmor.yml`), `version`,
`runs-on`, and `container` for a runner without Python (Python and pip are installed in
it). This repository runs it on itself from `test.yml`, so a pull request here runs the
changed workflow before any caller moves its pin.

A repository's single required check (e.g. `CI success`) stays a job of its own that
`needs:` the calls: a reusable workflow's jobs report as `<caller job> / <job>`.

## Python (uv)

[`python-uv.yml`](.github/workflows/python-uv.yml) runs ruff, mypy and pytest through
`uv run` against the locked environment, so the tools are the project's own. Inputs:
`python-version`, `test-python-versions` (a JSON array), `mypy`, `build` (`uv build` and
`twine check`; needs a `release` dependency group with twine) and `check-uv-pins` (the uv
version agrees in `.devcontainer/Dockerfile`, `pyproject.toml` and
`.pre-commit-config.yaml`). Jobs particular to one project (a dependency's
lowest or newest version) stay in its CI, next to the call.

## Home Assistant

[`home-assistant.yml`](.github/workflows/home-assistant.yml) runs hassfest and the HACS
action on a custom integration. Inputs: `hacs-category` (default `integration`) and
`hacs-ignore`. Both validate against rules that change without a commit in the calling
repository, so callers also run it on a weekly schedule.

## Shell

[`shell.yml`](.github/workflows/shell.yml) checks scripts and dotfiles: shellcheck, `zsh -n`,
gitleaks over the history and optionally bats. Inputs: `shellcheck-pathspec`,
`zsh-pathspec`, `gitleaks`, `bats`, `bats-path`. gitleaks needs the secret
`GITLEAKS_LICENSE` in a repository of an organization; a personal account's repositories
need none.

## Renovate

[`renovate.yml`](.github/workflows/renovate.yml) runs Renovate as the GitHub App
`klconsultancy-renovate-bot`, at the version pinned here. Inputs: `app-client-id`
(`vars.RENOVATE_APP_CLIENT_ID`), `runs-on`, `renovate-image` and `renovate-version`; the
secret `RENOVATE_APP_PRIVATE_KEY`. The schedule is the caller's.

### Renovate in a calling repository

Extend the preset [`shared-workflows.json`](shared-workflows.json):

```json
{
  "extends": ["config:recommended", "helpers:pinGitHubActionDigests", "github>klconsultancy/workflows:shared-workflows"]
}
```

The pin on this repository then moves in a pull request of its own, **"shared workflows"**,
which waits for review, also where the repository automerges the rest:
`release-please.yml` and `renovate.yml` only run on `main`, and `claude-review.yml` skips
pull requests opened by a bot, so no check of the pull request runs a change to them, and a
broken one would land everywhere at once.

- **Automerge after all**, for a repository whose checks run every workflow it calls (no
  release-please, no Renovate, no Claude review): a rule of its own, after the preset's:
  `{"matchPackageNames": ["klconsultancy/workflows"], "automerge": true}`.
- **A rule that groups all actions** (`"matchManagers": ["github-actions"]` with a
  `groupName`) must leave the pin out with `"matchPackageNames": ["!klconsultancy/workflows"]`:
  the repository's rules come after the preset's, and would pull the pin back into that
  group, which would then wait for review with it.

## Changing a workflow here

Every change goes through a pull request. Pin actions to a full commit SHA with the version
in a comment, keep `permissions` minimal and `persist-credentials: false`, and check the
file with [actionlint](https://github.com/rhysd/actionlint) and
[zizmor](https://github.com/zizmorcore/zizmor); the Test workflow runs actionlint, zizmor,
shellcheck and the bats tests on every pull request, and `claude-review-check.yml` reviews the pull
request with this repository's Claude review workflow (main's: a pull request that changes
it gets no review, see above). Callers only pick a change up when their pin moves.

Renovate runs on this repository too (`renovate-run.yml`, through `renovate.yml` itself,
with [`renovate.json`](renovate.json)): it keeps the pins every caller shares current, the
actions as well as the Renovate and zizmor versions in the inputs' defaults. Those updates
wait for review: once merged, they reach every caller with its next pin update.
