#!/usr/bin/env bash
# Puts the review rules back to their base-branch version in the working tree, so a PR cannot
# change the rules it is reviewed against. Run inside the repository, checked out at the PR head.
#
#   rules.sh --base <ref> --head <sha> [--guidelines "<space-separated paths>"] --out <dir>
#
# Writes to <dir>:
#   changed-rules.txt  rules files the PR changes (added, edited or removed), one path per line
#   head-rules/<path>  the PR's version of each changed rules file that exists at the head
#   rules-files.txt    the rules in effect: each rules file as the base has it, one path per line
set -euo pipefail

base="" head="" guidelines="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --guidelines) guidelines="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) echo "rules.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$base" ] && [ -n "$head" ] && [ -n "$out" ] || { echo "rules.sh: --base, --head and --out are required" >&2; exit 2; }
mkdir -p "$out/head-rules"
: > "$out/changed-rules.txt"
: > "$out/rules-files.txt"

# blob <rev> <path>: the blob id, or nothing when the path does not exist at <rev>.
blob() { git rev-parse -q --verify "$1:$2" 2>/dev/null || true; }

# normalize <path>: resolve "." and ".." segments, without touching the file system.
normalize() {
  local IFS=/ part
  local -a parts=()
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..) [ ${#parts[@]} -gt 0 ] && unset 'parts[${#parts[@]}-1]' ;;
      *) parts+=("$part") ;;
    esac
  done
  printf '%s\n' "${parts[*]}"
}

# imports <rev> <path>: the repository files that <path> imports with @, as Claude Code reads them.
imports() {
  local dir
  dir=$(dirname "$2")
  git show "$1:$2" 2>/dev/null \
    | grep -oE '(^|[[:space:]])@[^[:space:]]+' \
    | sed -E 's/^[[:space:]]*@//; s/[.,;:)]+$//' \
    | grep -vE '^(~|/)' \
    | while read -r ref; do
        if [ "$dir" = . ]; then normalize "$ref"; else normalize "$dir/$ref"; fi
      done || true
}

# The rules: every CLAUDE.md and AGENTS.md (as either the base or the head has them), the
# guidelines, and everything the base versions import.
declare -A seen=()
queue=()
while read -r path; do queue+=("$path"); done < <(
  { git -c core.quotePath=false ls-tree -r --name-only "$base"; git -c core.quotePath=false ls-tree -r --name-only "$head"; } \
    | grep -E '(^|/)(CLAUDE|AGENTS)\.md$' | sort -u
)
for path in $guidelines; do queue+=("$(normalize "$path")"); done
while [ ${#queue[@]} -gt 0 ]; do
  path="${queue[0]}"
  queue=("${queue[@]:1}")
  [ -n "${seen[$path]:-}" ] && continue
  seen[$path]=1
  # Imports are followed as the base has them: what a PR newly imports is not a rule yet, just
  # a changed file (and the importing rules file shows up as changed).
  while read -r imported; do
    [ -n "$imported" ] && queue+=("$imported")
  done < <(imports "$base" "$path")
done

while IFS= read -r path; do
  base_blob=$(blob "$base" "$path")
  head_blob=$(blob "$head" "$path")
  [ -n "$base_blob" ] && echo "$path" >> "$out/rules-files.txt"
  [ "$base_blob" = "$head_blob" ] && continue
  echo "$path" >> "$out/changed-rules.txt"
  if [ -n "$head_blob" ]; then
    mkdir -p "$out/head-rules/$(dirname "$path")"
    git show "$head_blob" > "$out/head-rules/$path"
  fi
  if [ -n "$base_blob" ]; then
    mkdir -p "$(dirname "$path")"
    git show "$base_blob" > "$path"
  else
    rm -f "$path"
  fi
done < <(printf '%s\n' "${!seen[@]}" | sort)
