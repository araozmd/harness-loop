#!/bin/sh
# test_reviewer_self_improve.sh — E99-F190 (GitHub #349): the Reviewer's "Self-improving the
# harness" clause invites prompt and template edits only in the harness's own source repository.
# In an installed project those files are installer-owned (tools/harness-owned-paths.sh): the
# init.sh drift guard fails on any edit, and the next upgrade overwrites it. There the Reviewer
# records a lesson and reports upstream. Each pin runs on the real file (must pass) and on a
# mutant copy with the rule removed or the old wording back (must be rejected).
# Constraints: reads only; everything under $T.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REV="$ROOT/agents/reviewer.md"
T="$(mktemp -d 2>/dev/null || mktemp -d -t revself)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# section <file> <heading> — the text of one `## ` section, folded to single spaces. Fence-aware
# through the ONE shared copy of the CommonMark fence rule (tests/lib/fence.awk, E99-F131).
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
section() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = ($0 == h); next }
    keep' "$1" | tr '\n' ' ' | tr -s ' '
}

check() { # <file> — 0 when the clause is layout-aware
  _s="$(section "$1" '## Self-improving the harness')"
  [ -n "$_s" ] || { echo "no '## Self-improving the harness' section"; return 1; }
  printf '%s' "$_s" | grep -qiE 'in the harness.s own source repository \(no `\.harness/` directory at the repository root\)' \
    || { echo "the source-repository condition is missing"; return 1; }
  printf '%s' "$_s" | grep -qiE 'in an installed project \(`\.harness/` exists\)' \
    || { echo "the installed-project case is missing"; return 1; }
  printf '%s' "$_s" | grep -qiE 'never edit .*`\.harness/agents/`' \
    || { echo "the ban on editing installer-owned paths is missing"; return 1; }
  printf '%s' "$_s" | grep -qiE 'drift guard' \
    || { echo "the reason (the init.sh drift guard) is missing"; return 1; }
  printf '%s' "$_s" | grep -qiE 'record the lesson in the harness-root-relative `progress/lessons\.md`' \
    || { echo "the lessons-ledger route is missing"; return 1; }
  printf '%s' "$_s" | grep -qiE 'Reporting harness defects' \
    || { echo "the upstream-report route is missing"; return 1; }
  if printf '%s' "$_s" | grep -qiE 'you may \*\*update the harness itself\*\* — tighten'; then
    echo "the old unconditional invitation is back"; return 1; fi
  return 0
}

mutant() { # <out> <perl-expr>
  perl -0pe "$2" "$REV" > "$1"
  cmp -s "$REV" "$1" && fail "setup: the mutant '$2' did not apply"
  return 0
}

_o="$(check "$REV")" || fail "agents/reviewer.md: $_o"
pass "self_improving_clause_is_layout_aware"

_n=0
for _m in \
  's/ \(no `\.harness\/` directory at the repository\s+root\)//' \
  's/In an installed project \(`\.harness\/` exists\)/Elsewhere/' \
  's/Never edit\s+`\.harness\/agents\/`/Avoid editing `.harness\/agents\/`/' \
  's/record the lesson in the harness-root-relative `progress\/lessons\.md`/note the lesson somewhere/' \
  's/## Self-improving the harness\n\n/## Self-improving the harness\n\nIf you find the Builder failed because a rule was missing or ambiguous, you may\n**update the harness itself** — tighten `AGENTS.md`, an agent prompt, or a template.\n\n/'; do
  _n=$((_n + 1))
  mutant "$T/m$_n.md" "$_m"
  if check "$T/m$_n.md" >/dev/null; then fail "mutant $_n was not rejected: $_m"; fi
done
pass "self_improving_clause_mutants_rejected ($_n)"

echo "all reviewer self-improve checks passed"
