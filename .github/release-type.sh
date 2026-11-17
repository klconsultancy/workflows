#!/usr/bin/env bash
# release-type.sh <title> <base>: fails when a pull request changes what callers run but its
# title releases nothing.
#
# Callers pin a release of this repository, and release-please releases only for `feat`,
# `fix`, `perf`, `revert` or a breaking `!`. A change to a reusable workflow (a file with
# `workflow_call:`, at the base or the head) or to the scripts claude-review.yml runs
# (.github/claude-review/) under a `ci:` or `docs:` title would land on main and reach no
# caller. Run in a checkout of the pull request's head, with <base> (the base branch's
# commit) fetched.
set -euo pipefail

title=$1
base=$2

releasing='^(feat|fix|perf|revert)(\([^)]*\))?!?: |^[a-z]+(\([^)]*\))?!: '
if [[ $title =~ $releasing ]]; then
  echo "The title releases: \"$title\"."
  exit 0
fi

# Whether <file> is a reusable workflow at <rev>.
reusable_at() {
  git show "$2:$1" 2>/dev/null | grep -q '^[[:space:]]*workflow_call:'
}

shipped=()
while IFS= read -r file; do
  case $file in
    .github/claude-review/*) shipped+=("$file") ;;
    .github/workflows/*.yml | .github/workflows/*.yaml)
      if reusable_at "$file" HEAD || reusable_at "$file" "$base"; then
        shipped+=("$file")
      fi
      ;;
  esac
done < <(git diff --name-only "$base"...HEAD)

if ((${#shipped[@]} == 0)); then
  echo "Nothing callers run changes: any title will do."
  exit 0
fi

echo "::error::\"$title\" releases nothing, but this changes what callers run: ${shipped[*]}. Callers only get it in a release: title it fix:, feat:, perf: or revert: (with ! when callers must change something)."
exit 1
