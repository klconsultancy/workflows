# Shared by the bats tests. Load with `load helpers`.

# git_repo <dir>: a fresh repository on `main`, entered, ready to commit.
git_repo() {
  git init -q -b main "$1"
  cd "$1"
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
}

# commit <file> <content> [<message>]
commit() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  git add "$1" && git commit -qm "${3:-change $1}"
}

# fake_gh: put a `gh` on PATH whose `gh api <path> [flags]` prints the fixture stored for that
# path (see `fixture`), or fails like a 404.
fake_gh() {
  export FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FIXTURES" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
[ "$1" = api ] || { echo "fake gh: only 'api' is supported" >&2; exit 2; }
f="$FIXTURES/$(printf '%s' "$2" | tr '/?&=' '____')"
[ -f "$f" ] || { echo "fake gh: no fixture for $2" >&2; exit 1; }
cat "$f"
GH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# fixture <api path> <body>
fixture() {
  printf '%s' "$2" > "$FIXTURES/$(printf '%s' "$1" | tr '/?&=' '____')"
}

# refute_grep <pattern> <file>: fails when the pattern occurs.
refute_grep() {
  if grep -q -- "$1" "$2"; then echo "unexpected '$1' in $2" >&2; return 1; fi
}

# refute_listed <line> <file>: fails when the file has that exact line.
refute_listed() {
  if grep -qxF -- "$1" "$2"; then echo "unexpected '$1' in $2" >&2; return 1; fi
}
