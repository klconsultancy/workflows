#!/usr/bin/env bats
# last-reviewed.sh: the head SHA of the last run whose review job succeeded, from the Actions API.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../.github/claude-review/last-reviewed.sh"

setup() {
  fake_gh

  fixture repos/o/r/actions/runs/900 '{"id": 900, "workflow_id": 7}'
}

runs() { # runs <json array of workflow runs>
  fixture "repos/o/r/actions/workflows/7/runs?event=pull_request&branch=feat&status=completed&per_page=100" \
    "{\"workflow_runs\": $1}"
}

jobs() { # jobs <run id> <json array of jobs>
  fixture "repos/o/r/actions/runs/$1/jobs" "{\"jobs\": $2}"
}

last_reviewed() {
  run "$SCRIPT" --repo o/r --run-id 900 --pr 12 --head-branch feat
}

@test "skips the current run and runs whose review job did not succeed" {
  runs '[
    {"id": 900, "head_sha": "current", "pull_requests": [{"number": 12}]},
    {"id": 803, "head_sha": "cancelled", "pull_requests": [{"number": 12}]},
    {"id": 802, "head_sha": "reviewed", "pull_requests": [{"number": 12}]},
    {"id": 801, "head_sha": "older", "pull_requests": [{"number": 12}]}
  ]'
  jobs 900 '[{"name": "review / Review", "conclusion": "success"}]'
  jobs 803 '[{"name": "review / Review", "conclusion": "cancelled"}]'
  jobs 802 '[{"name": "review / Review", "conclusion": "success"}]'
  jobs 801 '[{"name": "review / Review", "conclusion": "success"}]'

  last_reviewed
  [ "$status" -eq 0 ]
  [ "$output" = reviewed ]
}

@test "a caller's other failing job does not void a successful review" {
  runs '[{"id": 802, "head_sha": "reviewed", "conclusion": "failure", "pull_requests": [{"number": 12}]}]'
  jobs 802 '[{"name": "lint", "conclusion": "failure"}, {"name": "review / Review", "conclusion": "success"}]'

  last_reviewed
  [ "$status" -eq 0 ]
  [ "$output" = reviewed ]
}

@test "ignores runs of another PR from the same branch" {
  runs '[
    {"id": 803, "head_sha": "other-pr", "pull_requests": [{"number": 7}]},
    {"id": 802, "head_sha": "reviewed", "pull_requests": [{"number": 12}]}
  ]'
  jobs 803 '[{"name": "review / Review", "conclusion": "success"}]'
  jobs 802 '[{"name": "review / Review", "conclusion": "success"}]'

  last_reviewed
  [ "$status" -eq 0 ]
  [ "$output" = reviewed ]
}

@test "no successful review yet: prints nothing" {
  runs '[{"id": 803, "head_sha": "failed", "pull_requests": [{"number": 12}]}]'
  jobs 803 '[{"name": "review / Review", "conclusion": "failure"}]'

  last_reviewed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
