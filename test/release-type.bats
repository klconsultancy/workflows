setup() {
  load helpers
  SCRIPT="$BATS_TEST_DIRNAME/../.github/release-type.sh"
  git_repo "$BATS_TEST_TMPDIR/repo"
  commit .github/workflows/shared.yml $'on:\n  workflow_call:'
  commit .github/workflows/test.yml $'on:\n  pull_request:'
  commit README.md "readme"
  git switch -q -c pr
}

@test "a ci: title that changes a reusable workflow fails" {
  commit .github/workflows/shared.yml $'on:\n  workflow_call:\n# changed'
  run "$SCRIPT" "ci: tweak the shared workflow" main
  [ "$status" -eq 1 ]
  [[ $output == *"releases nothing"*".github/workflows/shared.yml"* ]]
}

@test "a fix: or feat: title that changes a reusable workflow passes" {
  commit .github/workflows/shared.yml $'on:\n  workflow_call:\n# changed'
  run "$SCRIPT" "fix(shared): tweak" main
  [ "$status" -eq 0 ]
  run "$SCRIPT" "feat: tweak" main
  [ "$status" -eq 0 ]
}

@test "a breaking change of any type passes" {
  commit .github/workflows/shared.yml $'on:\n  workflow_call:\n# changed'
  run "$SCRIPT" "refactor!: rename an input" main
  [ "$status" -eq 0 ]
}

@test "a ci: title that changes only this repository's own workflows passes" {
  commit .github/workflows/test.yml $'on:\n  pull_request:\n# changed'
  commit README.md "readme, changed"
  run "$SCRIPT" "ci: run the tests on push" main
  [ "$status" -eq 0 ]
  [[ $output == *"any title will do"* ]]
}

@test "the scripts claude-review.yml runs count as shipped" {
  commit .github/claude-review/scope.sh "echo changed"
  run "$SCRIPT" "chore: tidy scope.sh" main
  [ "$status" -eq 1 ]
}

@test "removing a reusable workflow counts as shipped" {
  git rm -q .github/workflows/shared.yml && git commit -qm "remove"
  run "$SCRIPT" "chore: remove shared.yml" main
  [ "$status" -eq 1 ]
}

@test "a workflow that becomes reusable counts as shipped" {
  commit .github/workflows/new.yml $'on:\n  workflow_call:'
  run "$SCRIPT" "docs: add a workflow" main
  [ "$status" -eq 1 ]
}
