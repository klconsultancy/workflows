#!/usr/bin/env bash
# Decides what a review run covers, from git alone. Run inside the repository, at the PR head.
#
#   scope.sh --base <ref> --head <sha> [--last-reviewed <sha>] --out <dir>
#
# Writes to <dir>:
#   scope              full | <old>..<new> | none
#   reason             one line, why this scope
#   changes.diff       the diff to review (empty for none)
#   changed-files.txt  git name-status of that diff
#   skipped-files.txt  changed files left out of the diff, as "<reason><TAB><path>": reason
#                      `generated` (lock, minified, vendored) or `symlink` (never followed)
set -euo pipefail

# Generated content a reviewer cannot judge line by line. Kept out of the diff, listed as skipped.
skip=(
  ':(glob)**/*.lock' ':(glob)**/package-lock.json' ':(glob)**/pnpm-lock.yaml' ':(glob)**/go.sum'
  ':(glob)**/*.min.js' ':(glob)**/*.min.css' ':(glob)**/*.map'
  ':(glob)**/vendor/**' ':(glob)**/node_modules/**'
)
exclude=("${skip[@]/#:(glob)/:(exclude,glob)}")

base="" head="" last="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --last-reviewed) last="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) echo "scope.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$base" ] && [ -n "$head" ] && [ -n "$out" ] || { echo "scope.sh: --base, --head and --out are required" >&2; exit 2; }
mkdir -p "$out"

write_scope() { # write_scope <scope> <reason> <from> <to>
  local -a symlinks=() leave_out=("${exclude[@]}")
  local path
  # Symlinks at <to> (mode 120000): a reviewer reading one would follow it, maybe out of the
  # repository.
  while IFS= read -r path; do
    symlinks+=("$path")
    leave_out+=(":(exclude,literal)$path")
  done < <(git -c core.quotePath=false diff --raw --no-renames "$3" "$4" -- . "${exclude[@]}" \
    | awk -F '\t' '{ split($1, f, " "); if (f[2] == "120000") print $2 }')

  printf '%s\n' "$1" > "$out/scope"
  printf '%s\n' "$2" > "$out/reason"
  git diff "$3" "$4" -- . "${leave_out[@]}" > "$out/changes.diff"
  git diff --name-status "$3" "$4" -- . "${leave_out[@]}" > "$out/changed-files.txt"
  {
    git -c core.quotePath=false diff --name-only "$3" "$4" -- "${skip[@]}" | awk '{ print "generated\t" $0 }'
    for path in "${symlinks[@]}"; do printf 'symlink\t%s\n' "$path"; done
  } > "$out/skipped-files.txt"
}

fork_point=$(git merge-base "$base" "$head")
if [ -z "$last" ]; then
  write_scope full "first review" "$fork_point" "$head"
  exit 0
fi

# Unknown to this clone (dropped by a force-push and never fetched) also lands here.
if ! git merge-base --is-ancestor "$last" "$head" 2>/dev/null; then
  write_scope full "the last reviewed commit $last is no longer in the branch history (force-push or rebase)" "$fork_point" "$head"
  exit 0
fi

# Changes that came in from the base since the last review (a merge from the base,
# `gh pr update-branch`) are not the PR's own: compare the head with what the last reviewed
# commit would look like on the same base, not with the last reviewed commit itself.
from="$last"
if [ "$(git merge-base "$last" "$base")" != "$fork_point" ]; then
  # pipefail: a conflicting merge-tree (exit 1) fails the assignment.
  if ! from=$(git merge-tree --write-tree --no-messages "$last" "$fork_point" | head -n 1); then
    write_scope full "the base changes merged in since the last review conflict with it" "$fork_point" "$head"
    exit 0
  fi
fi

if git diff --quiet "$from" "$head"; then
  write_scope none "no new PR changes since the last review" "$head" "$head"
  exit 0
fi
write_scope "$last..$head" "changes since the last review" "$from" "$head"
