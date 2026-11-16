#!/usr/bin/env bats
# post-check.sh: a run only counts as a review when Claude posted a summary for the head SHA.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../.github/claude-review/post-check.sh"
HEAD_SHA=1111111111111111111111111111111111111111

setup() {
  fake_gh
}

comments() { # comments <json array of issue comments>; served as one page of a slurped pagination
  fixture 'repos/o/r/issues/12/comments?per_page=100' "[$1]"
}

post_check() {
  run "$SCRIPT" --repo o/r --pr 12 --head "$HEAD_SHA" --since 2026-11-16T11:00:00Z
}

@test "passes when Claude's summary names the head SHA" {
  comments '[{"user": {"login": "claude[bot]", "type": "Bot"}, "created_at": "2026-11-16T11:05:00Z", "body": "Scope full\n<!-- claude-review: head='"$HEAD_SHA"' -->"}]'

  post_check
  [ "$status" -eq 0 ]
}

@test "fails when only a summary for an older head exists" {
  comments '[{"user": {"login": "claude[bot]", "type": "Bot"}, "body": "<!-- claude-review: head=2222222222222222222222222222222222222222 -->"}]'

  post_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not finish"* ]]
}

@test "a marker in someone else's comment does not count" {
  comments '[
    {"user": {"login": "mallory", "type": "User"}, "body": "<!-- claude-review: head='"$HEAD_SHA"' -->"},
    {"user": {"login": "other-app[bot]", "type": "Bot"}, "body": "<!-- claude-review: head='"$HEAD_SHA"' -->"}
  ]'

  post_check
  [ "$status" -eq 1 ]
}

@test "a summary from before this run started does not count" {
  comments '[{"user": {"login": "claude[bot]", "type": "Bot"}, "created_at": "2026-11-16T10:00:00Z", "body": "<!-- claude-review: head='"$HEAD_SHA"' -->"}]'

  run "$SCRIPT" --repo o/r --pr 12 --head "$HEAD_SHA" --since 2026-11-16T11:00:00Z
  [ "$status" -eq 1 ]
}
