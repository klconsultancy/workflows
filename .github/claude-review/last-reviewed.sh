#!/usr/bin/env bash
# Prints the head SHA of the most recent run, for this PR, whose review job succeeded; prints
# nothing when there is none. Only the workflow can create such runs, so a comment cannot steer
# the scope. The job's conclusion counts, not the run's: callers may have other jobs.
#
#   last-reviewed.sh --repo <owner/name> --run-id <current run> --pr <number> --head-branch <branch>
#
# Needs `gh` with `actions: read`.
set -euo pipefail

repo="" run_id="" pr="" branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --head-branch) branch="$2"; shift 2 ;;
    *) echo "last-reviewed.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] && [ -n "$run_id" ] && [ -n "$pr" ] && [ -n "$branch" ] \
  || { echo "last-reviewed.sh: --repo, --run-id, --pr and --head-branch are required" >&2; exit 2; }

workflow_id=$(gh api "repos/$repo/actions/runs/$run_id" | jq -r .workflow_id)

branch_q=$(jq -rn --arg b "$branch" '$b | @uri')
# Newest first, as the API returns them.
gh api "repos/$repo/actions/workflows/$workflow_id/runs?event=pull_request&branch=$branch_q&status=completed&per_page=100" \
  | jq -r --argjson current "$run_id" --argjson pr "$pr" '
      .workflow_runs[]
      | select(.id != $current)
      # A branch can outlive its PR. The API leaves pull_requests empty at times; scope.sh
      # still checks that the SHA is an ancestor of the head.
      | select((.pull_requests | length) == 0 or any(.pull_requests[]; .number == $pr))
      | "\(.id) \(.head_sha)"' \
  | while read -r id sha; do
      conclusion=$(gh api "repos/$repo/actions/runs/$id/jobs" \
        | jq -r '[.jobs[] | select(.name == "Review" or (.name | endswith(" / Review")))][0].conclusion // ""')
      if [ "$conclusion" = success ]; then
        echo "$sha"
        break
      fi
    done
