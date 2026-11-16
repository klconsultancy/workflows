#!/usr/bin/env bats
# scope.sh: what a review run covers, from git alone.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../.github/claude-review/scope.sh"

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  OUT="$BATS_TEST_TMPDIR/out"
  git_repo "$REPO"
  printf 'one\ntwo\nthree\n' > app.py
  printf 'base doc\n' > README.md
  git add . && git commit -qm init
}

scope() { # scope [--last-reviewed <sha>]
  run "$SCRIPT" --base main --head "$(git rev-parse HEAD)" --out "$OUT" "$@"
}

@test "first review: full scope with only the PR's own changes" {
  git checkout -qb feature
  commit feature.py 'print(1)' 'feat'
  git checkout -q main
  commit README.md 'base moved on' 'base change'
  git checkout -q feature

  scope
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = full ]
  grep -q 'first review' "$OUT/reason"
  [ "$(cat "$OUT/changed-files.txt")" = "A	feature.py" ]
  grep -q 'print(1)' "$OUT/changes.diff"
  refute_grep 'base moved on' "$OUT/changes.diff"
}

@test "push after a review: only the commits since the reviewed SHA" {
  git checkout -qb feature
  commit feature.py 'print(1)' 'feat'
  reviewed=$(git rev-parse HEAD)
  commit fix.py 'print(2)' 'fix'

  scope --last-reviewed "$reviewed"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = "$reviewed..$(git rev-parse HEAD)" ]
  [ "$(cat "$OUT/changed-files.txt")" = "A	fix.py" ]
  refute_grep 'print(1)' "$OUT/changes.diff"
}

@test "force-push that drops the reviewed SHA: full review, says why" {
  git checkout -qb feature
  commit feature.py 'print(1)' 'feat'
  reviewed=$(git rev-parse HEAD)
  git reset -q --hard main
  commit feature.py 'print(10)' 'feat, rewritten'

  scope --last-reviewed "$reviewed"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = full ]
  grep -q 'force-push' "$OUT/reason"
  grep -q 'print(10)' "$OUT/changes.diff"
}

@test "push that only merges the base in: no new PR changes" {
  git checkout -qb feature
  commit feature.py 'print(1)' 'feat'
  reviewed=$(git rev-parse HEAD)
  git checkout -q main
  commit README.md 'base moved on' 'base change'
  git checkout -q feature
  git merge -q --no-edit main

  scope --last-reviewed "$reviewed"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = none ]
  grep -q 'no new PR changes' "$OUT/reason"
  [ ! -s "$OUT/changes.diff" ]
}

@test "own commit plus a base merge: only the own commit" {
  git checkout -qb feature
  commit feature.py 'print(1)' 'feat'
  reviewed=$(git rev-parse HEAD)
  git checkout -q main
  commit README.md 'base moved on' 'base change'
  git checkout -q feature
  git merge -q --no-edit main
  commit fix.py 'print(2)' 'fix'

  scope --last-reviewed "$reviewed"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = "$reviewed..$(git rev-parse HEAD)" ]
  [ "$(cat "$OUT/changed-files.txt")" = "A	fix.py" ]
}

@test "base merge that resolved conflicts: full review, says why" {
  git checkout -qb feature
  commit app.py 'feature version' 'feat'
  reviewed=$(git rev-parse HEAD)
  git checkout -q main
  commit app.py 'base version' 'base change'
  git checkout -q feature
  git merge -q --no-edit main || true
  printf 'resolved by hand\n' > app.py
  git add app.py && git commit -q --no-edit

  scope --last-reviewed "$reviewed"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/scope")" = full ]
  grep -q 'conflict' "$OUT/reason"
  grep -q 'resolved by hand' "$OUT/changes.diff"
}

@test "lock, minified and vendored files are listed as skipped, not in the diff" {
  git checkout -qb feature
  mkdir -p web vendor/lib
  printf 'lock\n' > uv.lock
  printf 'lock\n' > web/package-lock.json
  printf 'min\n' > web/app.min.js
  printf 'vendored\n' > vendor/lib/x.py
  commit feature.py 'print(1)' 'feat'
  git add . && git commit -qm 'generated'

  scope
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/changed-files.txt")" = "A	feature.py" ]
  [ "$(sort "$OUT/skipped-files.txt")" = "$(printf 'generated\t%s\n' uv.lock vendor/lib/x.py web/app.min.js web/package-lock.json)" ]
  refute_grep 'lock' "$OUT/changes.diff"
}

@test "a changed symlink is skipped, not read" {
  git checkout -qb feature
  ln -s /etc/passwd link
  git add link && git commit -qm 'add a symlink'
  commit feature.py 'print(1)' 'feat'

  scope
  [ "$status" -eq 0 ]
  [ "$(cat "$OUT/changed-files.txt")" = "A	feature.py" ]
  [ "$(cat "$OUT/skipped-files.txt")" = "symlink	link" ]
}
