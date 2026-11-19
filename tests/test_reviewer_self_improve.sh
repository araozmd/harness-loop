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
  _p() { printf '%s' "$_s" | grep -qiE -- "$1" || { echo "$2"; return 1; }; }
  _p 'In the harness.s own source repository \(the harness files sit at the repository root and there is no `\.harness/` directory\)' \
     "the source-repository condition is missing" || return 1
  _p 'In an installed project \(the harness you run from is a `\.harness/` directory carrying `\.harness-version`\)' \
     "the installed-project condition is missing" || return 1
  _p 'the installer-owned files are the ones the install manifest \(`\.harness/manifest\.txt`, "HARNESS-OWNED"\) says every upgrade overwrites: `\.harness/AGENTS\.md`, `\.harness/init\.sh`, `\.harness/agents/`, `\.harness/docs/`, `\.harness/store/`, `\.harness/tools/`, `\.harness/specs/_templates/`' \
     "the owned set is not the manifest's HARNESS-OWNED list" || return 1
  _p 'the `init\.sh` drift guard fails on an uncommitted edit to an installer-owned `\.harness/` file or to the glue `tools/harness-owned-paths\.sh` lists \(an untracked body only warns\)' \
     "the drift-guard reason is missing or overclaims" || return 1
  _p 'the next upgrade reinstalls a committed edit to those `\.harness/` files and the regenerated `\.claude/` and `\.opencode/command/` glue away' \
     "the committed-edit case (upgrade overwrite) is missing" || return 1
  _p 'Never edit an installer-owned file\.' \
     "the never-edit rule is missing" || return 1
  _p 'record the lesson in the harness-root-relative `progress/lessons\.md`' \
     "the lessons-ledger route is missing" || return 1
  _p 'own root `AGENTS\.md` or `CLAUDE\.md`, outside the `<!-- harness:begin -->`' \
     "the project-owned root entrypoint route is missing" || return 1
  _p 'append an upstream report under \*\*Reporting harness defects\*\*' \
     "the upstream-report route is missing" || return 1
  if printf '%s' "$_s" | grep -qiE 'fails on any edit|you may \*\*update the harness itself\*\*|everything under `\.harness/` is installer-owned|the wider set'; then
    echo "an old over-claim is back"; return 1; fi
  return 0
}

check_harness_doc() { # <file> — docs/agents/HARNESS.md carries the same qualification
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -qE 'in an installed project it records a lesson and reports the gap upstream instead' \
    || { echo "docs/agents/HARNESS.md lacks the installed-project qualification"; return 1; }
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
  's/there is no `\.harness\/` directory\)/there is a repository\)/' \
  's/directory carrying\s+`\.harness-version`\)/directory\)/' \
  's/`\.harness\/specs\/_templates\/`, the two/the two/' \
  's/ \(an untracked body only warns\)//' \
  's/reinstalls a committed edit to those/keeps a committed edit to those/' \
  's/`\.harness\/AGENTS\.md`,\s+`\.harness\/init\.sh`/`.harness\/init.sh`/' \
  's/Never edit an installer-owned file\./Avoid editing them./' \
  's/the installer-owned files are the ones/everything under `.harness\/` is installer-owned, and the files/' \
  's/record the lesson in the\s+harness-root-relative `progress\/lessons\.md`/note the lesson somewhere/' \
  's/own root `AGENTS\.md` or `CLAUDE\.md`, outside/own root files, outside/' \
  's/append an upstream report under \*\*Reporting harness defects\*\*/mention it/' \
  's/drift guard fails on an uncommitted edit/drift guard fails on any edit/'; do
  _n=$((_n + 1))
  mutant "$T/m$_n.md" "$_m"
  if check "$T/m$_n.md" >/dev/null; then fail "mutant $_n was not rejected: $_m"; fi
done
pass "self_improving_clause_mutants_rejected ($_n)"

_o="$(check_harness_doc "$ROOT/docs/agents/HARNESS.md")" || fail "$_o"
perl -0pe 's/it records a lesson and reports the gap upstream instead/it edits the installed prompts/' "$ROOT/docs/agents/HARNESS.md" > "$T/h.md"
cmp -s "$ROOT/docs/agents/HARNESS.md" "$T/h.md" && fail "setup: the HARNESS.md mutant did not apply"
if check_harness_doc "$T/h.md" >/dev/null; then fail "the HARNESS.md mutant was not rejected"; fi
pass "harness_doc_qualified (and its mutant rejected)"

echo "all reviewer self-improve checks passed"
