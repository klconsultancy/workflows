#!/usr/bin/env bats
# rules.sh: the rules a PR is reviewed against come from the base, not from the PR.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../.github/claude-review/rules.sh"

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  OUT="$BATS_TEST_TMPDIR/out"
  git_repo "$REPO"
  mkdir -p docs
  printf '@AGENTS.md\n' > CLAUDE.md
  printf 'Strict TDD.\nSee @docs/rules.md for more.\n' > AGENTS.md
  printf 'No globals.\n' > docs/rules.md
  printf 'Design: small modules.\n' > docs/design.md
  printf 'code\n' > app.py
  git add . && git commit -qm init
  git checkout -qb feature
}

rules() { # rules [--guidelines "<paths>"]
  run "$SCRIPT" --base main --head "$(git rev-parse HEAD)" --out "$OUT" "$@"
}

@test "a rules file changed by the PR is put back to the base version; the head version is kept aside" {
  commit AGENTS.md 'Anything goes.'

  rules
  [ "$status" -eq 0 ]
  grep -q 'Strict TDD' AGENTS.md
  grep -q 'Anything goes' "$OUT/head-rules/AGENTS.md"
  [ "$(cat "$OUT/changed-rules.txt")" = AGENTS.md ]
}

@test "files imported with @, recursively, are put back too" {
  commit docs/rules.md 'Globals are fine.'

  rules
  [ "$status" -eq 0 ]
  grep -q 'No globals' docs/rules.md
  grep -q 'Globals are fine' "$OUT/head-rules/docs/rules.md"
  [ "$(cat "$OUT/changed-rules.txt")" = docs/rules.md ]
}

@test "CLAUDE.md and AGENTS.md in subdirectories are covered" {
  mkdir -p pkg
  printf 'pkg rule\n' > pkg/CLAUDE.md
  git add pkg && git commit -qm 'pkg' && git branch -f main HEAD
  commit pkg/CLAUDE.md 'pkg rule, weakened'

  rules
  [ "$status" -eq 0 ]
  [ "$(cat pkg/CLAUDE.md)" = 'pkg rule' ]
  [ "$(cat "$OUT/changed-rules.txt")" = pkg/CLAUDE.md ]
}

@test "guidelines files are put back too, and listed with the rules in effect" {
  commit docs/design.md 'Design: whatever.'

  rules --guidelines "docs/design.md"
  [ "$status" -eq 0 ]
  grep -q 'small modules' docs/design.md
  [ "$(cat "$OUT/changed-rules.txt")" = docs/design.md ]
  [ "$(cat "$OUT/rules-files.txt")" = "$(printf '%s\n' AGENTS.md CLAUDE.md docs/design.md docs/rules.md)" ]
}

@test "a rules file only the PR has is removed, and kept aside for review" {
  commit "sub dir/AGENTS.md" 'New rules from the PR.'

  rules
  [ "$status" -eq 0 ]
  [ ! -e "sub dir/AGENTS.md" ]
  grep -q 'New rules' "$OUT/head-rules/sub dir/AGENTS.md"
  [ "$(cat "$OUT/changed-rules.txt")" = "sub dir/AGENTS.md" ]
  refute_listed "sub dir/AGENTS.md" "$OUT/rules-files.txt"
}

@test "a file the PR newly imports is not reset: only the base's imports are rules" {
  printf 'Strict TDD.\nSee @docs/rules.md and @app.py\n' > AGENTS.md
  printf 'code, changed by the PR\n' > app.py
  git add . && git commit -qm 'import app.py'

  rules
  [ "$status" -eq 0 ]
  [ "$(cat app.py)" = 'code, changed by the PR' ]
  refute_listed app.py "$OUT/rules-files.txt"
  [ "$(cat "$OUT/changed-rules.txt")" = AGENTS.md ]
}

@test "a rules file the PR turns into a symlink: the target is untouched, the file is the base's" {
  printf 'victim\n' > "$BATS_TEST_TMPDIR/victim.txt"
  git rm -q AGENTS.md && ln -s "$BATS_TEST_TMPDIR/victim.txt" AGENTS.md
  git add AGENTS.md && git commit -qm 'symlink AGENTS.md out'

  rules
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/victim.txt")" = victim ]
  [ ! -L AGENTS.md ]
  grep -q 'Strict TDD' AGENTS.md
}

@test "a symlink to a file inside the repository: that file is untouched too" {
  git rm -q AGENTS.md && ln -s app.py AGENTS.md
  git add AGENTS.md && git commit -qm 'symlink AGENTS.md to app.py'

  rules
  [ "$status" -eq 0 ]
  [ "$(cat app.py)" = code ]
  [ ! -L AGENTS.md ]
  grep -q 'Strict TDD' AGENTS.md
}

@test "a directory of rules files the PR turns into a symlink: nothing is written through it" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf 'victim\n' > "$BATS_TEST_TMPDIR/outside/rules.md"
  git rm -rq docs && ln -s "$BATS_TEST_TMPDIR/outside" docs
  git add docs && git commit -qm 'symlink docs out'

  rules
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/outside/rules.md")" = victim ]
  [ ! -L docs ]
  grep -q 'No globals' docs/rules.md
}
