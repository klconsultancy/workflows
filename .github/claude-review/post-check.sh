#!/usr/bin/env bash
# Fails unless the Claude app posted a summary comment on the PR that names the head SHA, so a
# run that ends without a summary is red and its push does not count as reviewed.
#
#   post-check.sh --repo <owner/name> --pr <number> --head <sha> --since <ISO 8601 UTC time>
#
# Only comments created at or after --since (this run's start) count: a summary an earlier run
# posted for the same head (a re-run, a reopened PR) does not prove this run finished.
#
# Needs `gh` with `pull-requests: read` / `issues: read`.
set -euo pipefail

repo="" pr="" head="" since=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    *) echo "post-check.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] && [ -n "$pr" ] && [ -n "$head" ] && [ -n "$since" ] \
  || { echo "post-check.sh: --repo, --pr, --head and --since are required" >&2; exit 2; }

marker="<!-- claude-review: head=$head -->"
found=$(gh api "repos/$repo/issues/$pr/comments?per_page=100" --paginate --slurp \
  | jq --arg marker "$marker" --arg since "$since" '
      [add[]
       # Only the Claude GitHub App counts: anyone else could paste the marker.
       | select(.user.login == "claude[bot]" and .user.type == "Bot")
       | select(.created_at >= $since)
       | select(.body | contains($marker))]
      | length')

if [ "$found" -eq 0 ]; then
  echo "::error::No review summary from Claude for $head: the review did not finish." >&2
  exit 1
fi
