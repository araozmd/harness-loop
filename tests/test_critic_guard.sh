#!/bin/sh
# test_critic_guard.sh — E99-F186 (GitHub #323): the doc-critic may write ONLY its note, and the
# generating agent proves it. Two halves:
#   1. tools/critic-guard.sh snapshot|verify — behavioural rows over a scratch directory.
#   2. prose pins — the single write destination in agents/doc-critic.md, the snapshot / verify /
#      lints-after / missing-note rules in agents/architect.md, and the same guard at the other
#      spawn sites. Each prose pin runs on the real file (must pass) AND on a mutant copy with the
#      rule removed or the old wording restored (the check must reject it).
# Constraints: no exact VERSION literal, no live spec or board writes; everything under $T.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GUARD="$ROOT/tools/critic-guard.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t criticguard)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── behavioural rows ───────────────────────────────────────────────────────────
[ -f "$GUARD" ] || fail "B0: tools/critic-guard.sh does not exist"
[ -x "$GUARD" ] || fail "B0: tools/critic-guard.sh is not executable"

W="$T/w"; mkdir -p "$W"
for f in spec plan tasks tests; do printf '%s v1\n' "$f" > "$W/f.$f.md"; done
SNAP="$T/run/critic-guard-feature-spec.snap"
run() { set +e; sh "$GUARD" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }
snap4() { run snapshot "$SNAP" "$W/f.spec.md" "$W/f.plan.md" "$W/f.tasks.md" "$W/f.tests.md"; }

snap4
[ "$rc" -eq 0 ] || fail "B1: snapshot of four existing files exited $rc: $(cat "$T/err")"
[ -f "$SNAP" ] || fail "B1: snapshot did not create $SNAP (its parent directory did not exist)"
run verify "$SNAP"
[ "$rc" -eq 0 ] || fail "B1: verify of an unchanged set exited $rc: $(cat "$T/out")"
grep -qE '^critic-guard: 4 files unchanged$' "$T/out" || fail "B1: verify summary is not '4 files unchanged': $(cat "$T/out")"
pass "B1: an unchanged set verifies, exit 0"

printf 'fabricated spec for another product\n' > "$W/f.plan.md"
run verify "$SNAP"
[ "$rc" -eq 1 ] || fail "B2: verify after a rewrite exited $rc, not 1"
grep -qxF "CHANGED | $W/f.plan.md" "$T/out" || fail "B2: the changed file is not named: $(cat "$T/out")"
[ "$(grep -c '^CHANGED | ' "$T/out")" -eq 1 ] || fail "B2: an unchanged file was named as changed: $(cat "$T/out")"
grep -qE '^critic-guard: 1 of 4 reviewed files changed$' "$T/out" || fail "B2: summary line wrong: $(cat "$T/out")"
pass "B2: a changed file exits 1 and is the only one named"

printf 'plan v1\n' > "$W/f.plan.md"
printf 'x\n' >> "$W/f.tests.md"; : > "$W/f.spec.md"
run verify "$SNAP"
[ "$rc" -eq 1 ] || fail "B3: verify exited $rc, not 1"
grep -qxF "CHANGED | $W/f.spec.md" "$T/out" && grep -qxF "CHANGED | $W/f.tests.md" "$T/out" \
  || fail "B3: both changed files (one truncated to empty, one appended) must be named: $(cat "$T/out")"
grep -qF "$W/f.plan.md" "$T/out" && fail "B3: a file restored to its original bytes is still reported"
pass "B3: every changed file is named, a truncation counts, a byte-for-byte restore verifies clean"

printf 'spec v1\n' > "$W/f.spec.md"; printf 'tests v1\n' > "$W/f.tests.md"
printf 'taske v1\n' > "$W/f.tasks.md"   # same length, one byte different
run verify "$SNAP"
[ "$rc" -eq 1 ] && grep -qxF "CHANGED | $W/f.tasks.md" "$T/out" || fail "B4: a same-size one-byte edit was not detected"
printf 'tasks v1\n' > "$W/f.tasks.md"
pass "B4: a same-size one-byte edit is detected"

rm -f "$W/f.tests.md"
run verify "$SNAP"
[ "$rc" -eq 1 ] || fail "B5: verify with a deleted file exited $rc, not 1"
grep -qxF "MISSING | $W/f.tests.md" "$T/out" || fail "B5: the deleted file is not reported MISSING: $(cat "$T/out")"
printf 'tests v1\n' > "$W/f.tests.md"
pass "B5: a deleted file exits 1 and is reported MISSING"

run snapshot "$T/s2.snap" "$W/f.spec.md" "$W/nope.md"
[ "$rc" -eq 2 ] || fail "B6: snapshot naming a missing file exited $rc, not 2"
[ ! -f "$T/s2.snap" ] || fail "B6: a failed snapshot left a partial snapshot file behind"
grep -qF "$W/nope.md" "$T/err" || fail "B6: stderr does not name the missing file"
run snapshot "$T/s3.snap"
[ "$rc" -eq 2 ] || fail "B6: snapshot with no files exited $rc, not 2"
run snapshot "$T/s4.snap" "$T/has space.md"
[ "$rc" -eq 2 ] || fail "B6: a path with whitespace exited $rc, not 2"
run verify "$T/absent.snap"
[ "$rc" -eq 2 ] || fail "B6: verify of an absent snapshot exited $rc, not 2"
run bogus
[ "$rc" -eq 2 ] || fail "B6: an unknown mode exited $rc, not 2"
run
[ "$rc" -eq 2 ] || fail "B6: no arguments exited $rc, not 2"
pass "B6: usage and setup errors exit 2, never 0 or 1"

# B6b: a forgotten snapshot-file argument must not clobber the first reviewed file (#323 round 1).
printf 'spec v1\n' > "$W/f.spec.md"
cp "$W/f.spec.md" "$T/spec.orig"
run snapshot "$W/f.spec.md" "$W/f.plan.md" "$W/f.tasks.md"
[ "$rc" -eq 2 ] || fail "B7: snapshot with no snapfile argument exited $rc, not 2"
cmp -s "$W/f.spec.md" "$T/spec.orig" || fail "B7: the guard overwrote a reviewed file with checksums"
grep -qF '.snap' "$T/err" || fail "B7: stderr does not name the .snap requirement"
run snapshot "$T/noext" "$W/f.spec.md"
[ "$rc" -eq 2 ] || fail "B7: a snapshot path without .snap exited $rc, not 2"
printf 'x\n' > "$W/a.snap"
run snapshot "$W/a.snap" "$W/a.snap" "$W/f.spec.md"
[ "$rc" -eq 2 ] || fail "B7: a snapfile that is one of the listed files exited $rc, not 2"
[ "$(cat "$W/a.snap")" = x ] || fail "B7: the listed snapfile was overwritten"
ln "$W/a.snap" "$W/hard.snap"
run snapshot "$W/hard.snap" "$W/a.snap"
[ "$rc" -eq 2 ] || fail "B7: a snapfile that is the same file as a listed one (hard link) exited $rc, not 2"
mkdir "$T/dir.snap"
run snapshot "$T/dir.snap" "$W/f.spec.md"
[ "$rc" -eq 2 ] || fail "B7: a snapfile that is a directory exited $rc, not 2"
pass "B7: a missing, mis-suffixed, listed or directory snapfile is refused and no reviewed file is touched"

printf 'x\n' > "$T/has space.md"
run snapshot "$T/ws.snap" "$T/has space.md"
[ "$rc" -eq 2 ] || fail "B8: an existing file whose path has whitespace exited $rc, not 2"
grep -qi 'whitespace' "$T/err" || fail "B8: stderr does not say whitespace: $(cat "$T/err")"
pass "B8: a path with whitespace is refused for that reason"

: > "$T/e.snap"
run verify "$T/e.snap"
[ "$rc" -eq 2 ] || fail "B9: an empty snapshot verified with $rc, not 2"
printf 'garbage\n' > "$T/m1.snap"; run verify "$T/m1.snap"
[ "$rc" -eq 2 ] || fail "B9: a malformed snapshot line exited $rc, not 2"
printf 'abc 12 %s\n' "$W/f.spec.md" > "$T/m2.snap"; run verify "$T/m2.snap"
[ "$rc" -eq 2 ] || fail "B9: a non-numeric checksum exited $rc, not 2"
snap4; run verify "$SNAP" extra
[ "$rc" -eq 2 ] || fail "B9: verify with an extra argument exited $rc, not 2"
run restore "$SNAP" extra
[ "$rc" -eq 2 ] || fail "B9: restore with an extra argument exited $rc, not 2"
printf '%s' "$(cat "$SNAP")" > "$T/nonl.snap"   # same lines, final newline stripped
run verify "$T/nonl.snap"
[ "$rc" -eq 0 ] && grep -qE '^critic-guard: 4 files unchanged$' "$T/out" \
  || fail "B9: a snapshot whose last line lacks a newline lost that file (rc $rc: $(cat "$T/out"))"
printf 'tampered\n' > "$W/f.tests.md"
run verify "$T/nonl.snap"
[ "$rc" -eq 1 ] && grep -qxF "CHANGED | $W/f.tests.md" "$T/out" \
  || fail "B9: a change to the unterminated last snapshot line's file was not seen"
printf 'tests v1\n' > "$W/f.tests.md"
# B9b: each field of a snapshot line is validated on its own (size, path).
printf '123 abc %s\n' "$W/f.spec.md" > "$T/m3.snap"; run verify "$T/m3.snap"
[ "$rc" -eq 2 ] || fail "B9: a non-numeric size exited $rc, not 2"
printf '123 4\n' > "$T/m4.snap"; run verify "$T/m4.snap"
[ "$rc" -eq 2 ] || fail "B9: a snapshot line with no path exited $rc, not 2"
printf '123 4 %s extra\n' "$W/f.spec.md" > "$T/m5.snap"; run verify "$T/m5.snap"
[ "$rc" -eq 2 ] || fail "B9: a snapshot line whose path holds whitespace exited $rc, not 2"
pass "B9: an empty or malformed snapshot and extra arguments exit 2; an unterminated last line is still checked"

# B10: restore puts changed and missing files back byte for byte, exit 0 only when they match.
snap4
for f in spec plan tasks tests; do cp "$W/f.$f.md" "$T/orig.$f"; done
printf 'fabricated\n' > "$W/f.plan.md"; rm -f "$W/f.tests.md"
run restore "$SNAP"
[ "$rc" -eq 0 ] || fail "B10: restore exited $rc: $(cat "$T/out") $(cat "$T/err")"
for f in spec plan tasks tests; do cmp -s "$W/f.$f.md" "$T/orig.$f" || fail "B10: f.$f.md is not byte-identical after restore"; done
grep -qxF "RESTORED | $W/f.plan.md" "$T/out" && grep -qxF "RESTORED | $W/f.tests.md" "$T/out" \
  || fail "B10: restore does not name what it restored: $(cat "$T/out")"
grep -qF "RESTORED | $W/f.spec.md" "$T/out" && fail "B10: restore touched an unchanged file"
grep -qE '^critic-guard: 4 files unchanged$' "$T/out" || fail "B10: restore did not end in a clean verify: $(cat "$T/out")"
run restore "$SNAP"
[ "$rc" -eq 0 ] || fail "B10: restore of an unchanged set exited $rc"
printf 'bad\n' > "$W/f.spec.md"; rm -rf "$SNAP.d"
run restore "$SNAP"
[ "$rc" -eq 1 ] || fail "B10: restore with the byte copies gone exited $rc, not 1"
grep -qxF "UNRESTORABLE | $W/f.spec.md" "$T/out" || fail "B10: the unrestorable file is not reported UNRESTORABLE: $(cat "$T/out")"
[ "$(cat "$W/f.spec.md")" = bad ] || fail "B10: a file with no byte copy was modified"
cp "$T/orig.spec" "$W/f.spec.md"
run restore "$T/absent.snap"
[ "$rc" -eq 2 ] || fail "B10: restore of an absent snapshot exited $rc, not 2"
snap4; : > "$W/f.spec.md"; run restore "$SNAP"
cmp -s "$W/f.spec.md" "$T/orig.spec" || fail "B10: a truncated file was not restored"
mkdir -p "$W/sub"; printf 'deep v1\n' > "$W/sub/deep.md"
run snapshot "$T/deep.snap" "$W/sub/deep.md" "$W/f.plan.md"
rm -rf "$W/sub"
run restore "$T/deep.snap"
[ "$rc" -eq 0 ] && [ "$(cat "$W/sub/deep.md")" = "deep v1" ] || fail "B10: a file whose directory vanished was not restored (rc $rc)"
run snapshot "$T/deep.snap" "$W/f.spec.md"
[ "$(ls "$T/deep.snap.d" | wc -l | tr -d ' ')" -eq 1 ] || fail "B10: a re-snapshot left stale byte copies behind"
# B10b: a tampered byte copy is never copied over the reviewed file (restore checks the copy first).
snap4
printf 'critic rewrote this\n' > "$W/f.spec.md"
printf 'spec v2\n' > "$SNAP.d/1"   # same size as 'spec v1', different bytes: a size-only check would accept it
run restore "$SNAP"
[ "$rc" -eq 1 ] || fail "B10: restore from a tampered copy exited $rc, not 1"
grep -qxF "UNRESTORABLE | $W/f.spec.md" "$T/out" || fail "B10: a tampered copy is not reported UNRESTORABLE: $(cat "$T/out")"
[ "$(cat "$W/f.spec.md")" = "critic rewrote this" ] || fail "B10: the tampered copy was copied over the file"
grep -qF 'RESTORED' "$T/out" && fail "B10: restore claimed RESTORED from a tampered copy"
cp "$T/orig.spec" "$W/f.spec.md"
pass "B10: restore returns changed and missing files byte for byte; exit 0 only on a clean verify"

# ── prose helpers ──────────────────────────────────────────────────────────────
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
# section <file> <heading-prefix> — one `## ` section, fence-aware, folded onto one line.
section() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = (index($0, h) == 1); next }
    keep' "$1" | tr '\n' ' ' | tr -s ' '
}
# every check_* takes a FILE and returns 0 when it holds; a mutant must make it return non-zero.
re() { grep -qiE -- "$1"; }

FAILRE='If `restore` exits non-zero \(exit 1: a file is UNRESTORABLE or still differs; exit 2: the snapshot is gone or malformed\) the file is not trusted: rebuild it from your own last write, or with `git checkout -- <file>` when it is committed and unchanged since, then run `verify` again \(compare it by hand if the snapshot is unusable\); do not (hand off|continue) until the file is confirmed, and if it cannot be confirmed stop and report to the Orchestrator'
LIMITRE='detects a rewrite of the reviewed files unless the critic also rewrote the snapshot or its byte copies, which are not guarded'

check_critic() {
  _s="$(section "$1" '## Write scope')"
  [ -n "$_s" ] || { echo "no '## Write scope' section"; return 1; }
  printf '%s' "$_s" | re 'only file you may write is your note, `progress/<run>/doc-critic-<checkpoint>\.md`' \
    || { echo "single write destination missing"; return 1; }
  printf '%s' "$_s" | re 'never edit, create or overwrite any other file' || { echo "ban on other files missing"; return 1; }
  printf '%s' "$_s" | re 'document you review' || { echo "reviewed documents not named as off limits"; return 1; }
  if grep -qiE 'inline fixes|fix applied|fixes inline|fixes applied|similarly scoped' "$1"; then
    echo "old write-the-fix wording is still present"; return 1; fi
  if tr '\n' ' ' < "$1" | tr -s ' ' | grep -qiE 'review or edit a document|the critic never edits them'; then
    echo "a wording that implies editing passed documents is fine, or states non-editing as fact, is present"; return 1; fi
  _o="$(section "$1" '## Output summary')"
  printf '%s' "$_o" | re 'the issues found, each with the proposed fix' || { echo "note bullet does not say proposed fix"; return 1; }
  printf '%s' "$_s" | re 'matches the checksum the snapshot recorded' || { echo "Write scope over-claims the restore"; return 1; }
  _a="$(section "$1" '## Advisory-only behavior')"
  printf '%s' "$_a" | re 'critic must not edit them[^)]*unless the critic also rewrote the snapshot or its byte copies, which are not guarded' || { echo "advisory section does not say the critic must not edit"; return 1; }
  return 0
}

# snapdir_rules — the snapshot-directory rules every spawn site carries, over the folded section in $_s.
snapdir_rules() {
  printf '%s' "$_s" | re 'directory for the snapshot that you never name to the critic \(run `mktemp -d`, note the absolute path it prints[^.]*a shell variable may not survive between tool calls[^.]*write that literal path, shown here as `<snapdir>`, into every `snapshot`, `verify` and `restore` command\)' \
    || { echo "the mktemp / literal-path rule is missing"; return 1; }
  printf '%s' "$_s" | re 'critic-guard\.sh" snapshot <snapdir>/' || { echo "snapshot does not use the literal <snapdir> path"; return 1; }
  printf '%s' "$_s" | re 'critic-guard\.sh" verify <snapdir>/' || { echo "verify does not use the literal <snapdir> path"; return 1; }
  printf '%s' "$_s" | re 'critic-guard\.sh" restore <snapdir>/' || { echo "restore does not use the literal <snapdir> path"; return 1; }
  if printf '%s' "$_s" | grep -qF '$snapdir'; then echo 'the shell-variable form $snapdir is back (it may not survive between tool calls)'; return 1; fi
  printf '%s' "$_s" | re 'makes that unlikely, not impossible' || { echo "the unlikely-not-impossible limit is missing"; return 1; }
  printf '%s' "$_s" | re 'Remove the directory \(`rm -rf <snapdir>`\) after the last `verify` or `restore` of this checkpoint' \
    || { echo "the temp-directory removal sentence is missing"; return 1; }
  return 0
}

check_architect() {
  _s="$(section "$1" '## Doc-critic checkpoint before')"
  [ -n "$_s" ] || { echo "no checkpoint section"; return 1; }
  printf '%s' "$_s" | re 'Before the spawn, remove any note already at the path you passed[^.]*rm -f progress/<run>/doc-critic-feature-spec\.md' \
    || { echo "no stale-note removal before the spawn"; return 1; }
  snapdir_rules || return 1
  printf '%s' "$_s" | re 'Exit 2 from `snapshot` means no new snapshot was taken \(an older one at that path may remain\): fix the invocation and run it again before spawning' \
    || { echo "snapshot exit 2 is not fix-and-retry-before-spawning, or over-claims"; return 1; }
  printf '%s' "$_s" | re 'As soon as the critic returns, before you read its findings, run `sh "\$HARNESS_DIR/tools/critic-guard\.sh" verify <snapdir>/' \
    || { echo "no verify-after rule"; return 1; }
  printf '%s' "$_s" | re 'Exit 1 names each file that changed or vanished: run `sh "\$HARNESS_DIR/tools/critic-guard\.sh" restore ' \
    || { echo "exit 1 does not lead to the restore verb"; return 1; }
  printf '%s' "$_s" | re 'record the incident in the progress note, treat the checkpoint as failed and apply none of that critic.s findings' \
    || { echo "findings of a tampering critic are not discarded"; return 1; }
  printf '%s' "$_s" | re 'Exit 2 from `verify` means the files are unverified:[^.]*run `restore`[^.]*failed[^.]*no findings' \
    || { echo "verify exit 2 is not handled as unverified + failed"; return 1; }
  printf '%s' "$_s" | re 'no note at the path you passed[^.]*failed checkpoint' || { echo "a missing note is not a failed checkpoint"; return 1; }
  printf '%s' "$_s" | re 'Whether or not the checkpoint failed, run `tasks-pair-check`, `plan-cite-check` and `readiness-check` again after the critic returns and before hand-off' \
    || { echo "lints are not run unconditionally after the critic"; return 1; }
  printf '%s' "$_s" | re 'same working directory' || { echo "same-cwd rule missing"; return 1; }
  printf '%s' "$_s" | re "$FAILRE" || { echo "no instruction for a failed restore"; return 1; }
  printf '%s' "$_s" | re "$LIMITRE" || { echo "the residual-limit sentence is missing"; return 1; }
  printf '%s' "$_s" | re 'it exits 0 only when every file matches that recorded checksum' || { echo "restore over-claims what exit 0 proves"; return 1; }
  return 0
}

check_spawn_site() { # <file> <heading-prefix> <note-path-fragment> — planner / driller checkpoint sections
  _s="$(section "$1" "$2")"
  [ -n "$_s" ] || { echo "no section $2"; return 1; }
  printf '%s' "$_s" | re 'Before the spawn, remove any note already at `[^`]*doc-critic-[a-z-]+\.md` \(`rm -f`\)' || { echo "no stale-note removal"; return 1; }
  snapdir_rules || return 1
  printf '%s' "$_s" | re 'before applying any finding, run `sh "[^"]*critic-guard\.sh" verify' || { echo "verify is not before applying findings"; return 1; }
  printf '%s' "$_s" | re 'If it exits 1, run `sh "[^"]*critic-guard\.sh" restore' || { echo "no restore on exit 1"; return 1; }
  printf '%s' "$_s" | re 'apply none of that critic.s findings' || { echo "findings not discarded"; return 1; }
  printf '%s' "$_s" | re '`verify` exit 2 means the files are unverified' || { echo "verify exit 2 not handled"; return 1; }
  printf '%s' "$_s" | re 'exit 2 means no new snapshot was taken \(an older one at that path may remain\)' || { echo "snapshot exit 2 not handled"; return 1; }
  printf '%s' "$_s" | re 'one working directory' || { echo "same-cwd rule missing"; return 1; }
  printf '%s' "$_s" | re "$FAILRE" || { echo "no instruction for a failed restore"; return 1; }
  printf '%s' "$_s" | re "$LIMITRE" || { echo "the residual-limit sentence is missing"; return 1; }
  return 0
}

check_planner_gap() { # the board rewrite gap is stated, not implied covered
  _s="$(section "$1" '## Doc-critic checkpoint after')"
  printf '%s' "$_s" | re 'catches only a malformed board; a well-formed rewrite of `[^`]*state/tasks\.json` by the critic is an accepted, unguarded gap' \
    || { echo "the unguarded board gap is not stated"; return 1; }
  return 0
}

expect_ok()  { _r="$1"; shift; _m="$("$@" 2>&1)" || fail "$_r: real file rejected: $_m"; }
expect_bad() { # <row> <check> <mutant-file> [extra-args]
  _r="$1"; shift
  _m="$("$@" 2>&1)" && fail "$_r: the check accepted a mutant that removes the rule" || true; }
mutant() { # <src> <out> <sed-expr...> — apply the edit and prove it changed the file
  _src="$1"; _out="$2"; shift 2
  sed "$@" "$_src" > "$_out"
  cmp -s "$_src" "$_out" && fail "mutant setup: the sed edit did not change $_src ($*)" || true
}

# pmut <src> <out> <regex> <replacement> — regex mutant (\s+ spans wrapped lines); proves it applied.
pmut() {
  python3 -I - "$1" "$2" "$3" "$4" <<'PY' || fail "mutant setup: pattern did not match in $1: $3"
import re, sys
src, out, pat, rep = sys.argv[1:5]
t = open(src).read()
n, k = re.subn(re.sub(r" +", lambda m: r"\s+", pat), lambda m: rep, t, count=1)
if k != 1:
    sys.exit(1)
open(out, "w").write(n)
PY
}

CRITIC="$ROOT/agents/doc-critic.md"
ARCH="$ROOT/agents/architect.md"
PLANNER="$ROOT/agents/planner.md"
DRILLER="$ROOT/agents/driller.md"

# ── doc-critic.md: one write destination, no write-the-fix wording ─────────────
expect_ok "C1" check_critic "$CRITIC"
mutant "$CRITIC" "$T/c-m1.md" 's/## Write scope/## Scope of writes/'
expect_bad "C1 mutant: section renamed away" check_critic "$T/c-m1.md"
mutant "$CRITIC" "$T/c-m2.md" 's/only file you may write is your note/only file you may write is any note/'
expect_bad "C1 mutant: destination loosened" check_critic "$T/c-m2.md"
mutant "$CRITIC" "$T/c-m3.md" 's/never edit, create or overwrite any other file/never edit any other file/'
expect_bad "C1 mutant: create/overwrite dropped" check_critic "$T/c-m3.md"
mutant "$CRITIC" "$T/c-m4.md" 's/each with the proposed fix/each with the fix applied/'
expect_bad "C1 mutant: 'fix applied' restored" check_critic "$T/c-m4.md"
mutant "$CRITIC" "$T/c-m5.md" 's/^## Output summary$/## Output summary\n\nIn addition to inline fixes, write a note./'
expect_bad "C1 mutant: 'inline fixes' reintroduced" check_critic "$T/c-m5.md"
mutant "$CRITIC" "$T/c-m6.md" 's/the generating agent applies the fixes you propose/the generating agent applies fixes inline/'
expect_bad "C1 mutant: 'applies fixes inline' reintroduced" check_critic "$T/c-m6.md"
pmut "$CRITIC" "$T/c-m7.md" 'never review a document the caller did not pass' 'never review or edit a document the caller did not pass'
expect_bad "C1 mutant: 'review or edit a document the caller did not pass' restored" check_critic "$T/c-m7.md"
pmut "$CRITIC" "$T/c-m8.md" 'the critic must not edit them; the caller.s `critic-guard.sh` verify detects it if it does' 'the critic never edits them'
expect_bad "C1 mutant: the never-edits fact restored" check_critic "$T/c-m8.md"
pmut "$CRITIC" "$T/c-m9.md" ', unless the critic also rewrote the snapshot or its byte copies, which are not guarded\)' ')'
expect_bad "C1 mutant: residual limit deleted from the advisory section" check_critic "$T/c-m9.md"
pmut "$CRITIC" "$T/c-m10.md" 'when that copy matches the checksum the snapshot recorded' 'unconditionally'
expect_bad "C1 mutant: restore over-claim" check_critic "$T/c-m10.md"
pass "C1: doc-critic.md has one write destination, no write-the-fix wording and states the guard's limit (10 mutants rejected)"

# ── architect.md: stale note, snapshot, verify, restore, exit 2 split, lints unconditional ──
expect_ok "A1" check_architect "$ARCH"
amut() { pmut "$ARCH" "$T/a-$1.md" "$2" "$3"; expect_bad "A1 mutant $1: $4" check_architect "$T/a-$1.md"; }
amut 1 'Before the spawn, remove any note already at the path you passed' 'Before the spawn, note the path you passed' "stale note not removed"
amut 2 'critic-guard\.sh" snapshot <snapdir>' 'critic-guard.sh" record <snapdir>' "no snapshot"
amut 12 'Make a directory for the snapshot that you never name to the critic' 'Put the snapshot in progress/<run>/' "snapshot kept where the critic can be told of it"
amut 13 'If `restore` exits non-zero' 'If `restore` exits zero' "failed-restore instruction dropped"
amut 14 'stop and report to the Orchestrator' 'carry on' "failed-restore escalation dropped"
amut 15 'unless the critic also rewrote the snapshot or its byte copies, which are not guarded' 'always' "residual limit deleted"
amut 18 'verify <snapdir>/feature-spec\.snap`' 'verify "$snapdir/feature-spec.snap"`' "the \$snapdir shell-variable form reintroduced in verify"
amut 19 'run `mktemp -d`, note the absolute path it prints' 'run `mktemp -d` once' "literal-path rule dropped"
amut 20 'makes that unlikely, not impossible' 'makes that impossible' "limit over-claimed"
amut 21 'Remove the directory \(`rm -rf <snapdir>`\)' 'Leave the directory' "temp directory removal dropped"
amut 17 'it exits 0 only when every file matches that recorded checksum' 'it exits 0 only when every file matches' "restore exit-0 over-claim"
amut 3 'Exit 2 from `snapshot` means no new snapshot was taken \(an older one at that path may remain\): fix the invocation and run it again before spawning' 'Exit 2 from `snapshot` means no snapshot exists: carry on' "snapshot exit 2 over-claim or ignored"
amut 4 'As soon as the critic returns, before you read its findings, run' 'After the critic returns, run' "verify not before findings"
amut 5 'critic-guard\.sh" verify <snapdir>' 'critic-guard.sh" check <snapdir>' "no verify"
amut 6 'run `sh "\$HARNESS_DIR/tools/critic-guard\.sh" restore' 'rewrite them from your own last write, `sh "$HARNESS_DIR/tools/critic-guard.sh" list' "restore verb dropped (model-memory restore)"
amut 7 'treat the checkpoint as failed and apply none of that critic.s findings' "treat the checkpoint as failed and apply that critic's findings" "tampering critic findings kept"
amut 8 'Exit 2 from `verify` means\s+the files are unverified' 'Exit 2 from `verify` means the guard did not run' "verify exit 2 not unverified"
amut 9 'no note at the path you passed' 'a note at the path you passed' "missing note not a failure"
amut 10 'Whether or not the checkpoint failed, run' 'After applying findings, run' "lints conditional on applying findings"
amut 11 'same\s+working\s+directory' 'any working directory' "cwd rule dropped"
pass "A1: architect.md checkpoint removes a stale note, snapshots, verifies, restores via the verb, splits exit 2, fails a missing note and runs the lints unconditionally (16 mutants rejected)"

# ── the other spawn sites ──────────────────────────────────────────────────────
H='## Doc-critic checkpoint after'
expect_ok "P1" check_spawn_site "$PLANNER" "$H"
expect_ok "P2" check_planner_gap "$PLANNER"
expect_ok "D1" check_spawn_site "$DRILLER" "$H"
for _f in planner driller; do
  case "$_f" in planner) _src="$PLANNER" ;; *) _src="$DRILLER" ;; esac
  pmut "$_src" "$T/$_f-1.md" 'Before the spawn, remove any note' 'Before the spawn, read any note'
  expect_bad "$_f mutant: stale note" check_spawn_site "$T/$_f-1.md" "$H"
  pmut "$_src" "$T/$_f-2.md" 'critic-guard\.sh" snapshot' 'critic-guard.sh" record'
  expect_bad "$_f mutant: snapshot" check_spawn_site "$T/$_f-2.md" "$H"
  pmut "$_src" "$T/$_f-3.md" 'before applying any finding, run' 'after applying findings, run'
  expect_bad "$_f mutant: verify before findings" check_spawn_site "$T/$_f-3.md" "$H"
  pmut "$_src" "$T/$_f-4.md" 'If it exits 1, run `sh "[^"]*critic-guard\.sh" restore' 'If it exits 1, rewrite the files from memory, `sh "x" list'
  expect_bad "$_f mutant: restore verb" check_spawn_site "$T/$_f-4.md" "$H"
  pmut "$_src" "$T/$_f-5.md" 'apply none of that critic.s findings' 'apply that critic is findings'
  expect_bad "$_f mutant: findings kept" check_spawn_site "$T/$_f-5.md" "$H"
  pmut "$_src" "$T/$_f-6.md" '`verify` exit 2 means the files are unverified' '`verify` exit 2 means all is well'
  expect_bad "$_f mutant: verify exit 2" check_spawn_site "$T/$_f-6.md" "$H"
  pmut "$_src" "$T/$_f-7.md" 'exit 2 means no new snapshot was taken' 'exit 2 means fine'
  expect_bad "$_f mutant: snapshot exit 2" check_spawn_site "$T/$_f-7.md" "$H"
  pmut "$_src" "$T/$_f-8.md" 'one working directory' 'any directory'
  expect_bad "$_f mutant: cwd" check_spawn_site "$T/$_f-8.md" "$H"
  pmut "$_src" "$T/$_f-9.md" 'If `restore` exits non-zero' 'If `restore` exits zero'
  expect_bad "$_f mutant: failed-restore instruction" check_spawn_site "$T/$_f-9.md" "$H"
  pmut "$_src" "$T/$_f-10.md" 'stop and report to the Orchestrator' 'carry on'
  expect_bad "$_f mutant: failed-restore escalation" check_spawn_site "$T/$_f-10.md" "$H"
  pmut "$_src" "$T/$_f-11.md" 'unless the critic also rewrote the snapshot or its byte copies, which are not guarded' 'always'
  expect_bad "$_f mutant: residual limit" check_spawn_site "$T/$_f-11.md" "$H"
  pmut "$_src" "$T/$_f-12.md" 'directory for the snapshot that you never name to the critic' 'directory'
  expect_bad "$_f mutant: snapshot directory" check_spawn_site "$T/$_f-12.md" "$H"
  pmut "$_src" "$T/$_f-14.md" 'verify <snapdir>/' 'verify "$snapdir/'
  expect_bad "$_f mutant: \$snapdir shell-variable form" check_spawn_site "$T/$_f-14.md" "$H"
  pmut "$_src" "$T/$_f-15.md" 'run `mktemp -d`, note the absolute path it prints' 'run `mktemp -d` once'
  expect_bad "$_f mutant: literal-path rule" check_spawn_site "$T/$_f-15.md" "$H"
  pmut "$_src" "$T/$_f-16.md" 'makes that unlikely, not impossible' 'makes that impossible'
  expect_bad "$_f mutant: limit over-claimed" check_spawn_site "$T/$_f-16.md" "$H"
  pmut "$_src" "$T/$_f-17.md" 'Remove the directory \(`rm -rf <snapdir>`\)' 'Leave the directory'
  expect_bad "$_f mutant: directory removal" check_spawn_site "$T/$_f-17.md" "$H"
  pmut "$_src" "$T/$_f-13.md" 'exit 2 means no new snapshot was taken \(an older one at that path may remain\)' 'exit 2 means no snapshot exists'
  expect_bad "$_f mutant: exit-2 over-claim" check_spawn_site "$T/$_f-13.md" "$H"
done
pmut "$PLANNER" "$T/planner-9.md" 'catches only a malformed board; a well-formed rewrite of `[^`]*` by the critic is an accepted,\s+unguarded gap' 'covers the board.'
expect_bad "planner mutant: board gap unstated" check_planner_gap "$T/planner-9.md"
pass "P1/P2/D1: planner and driller carry the full guard protocol; the planner states its board gap (17 mutants rejected)"

# installer emitters: /sdd-plan and /sdd-drill bodies, the architect shim, the doc-critic shim.
INST="$ROOT/harness-install.sh"
cnt() { grep -cF -- "$1" "$2" || true; }
check_installer() { # <installer-copy>; each emitter (/sdd-plan, /sdd-drill) must carry each rule, so count >= 2
  for _p in '.harness/tools/critic-guard.sh" snapshot <snapdir>/' '.harness/tools/critic-guard.sh" verify <snapdir>/' \
            '.harness/tools/critic-guard.sh" restore <snapdir>/' '(`rm -f`), so a stale note cannot pass' \
            'If `restore` exits non-zero' 'do not continue until the file is confirmed' \
            'unless the critic also rewrote the snapshot or its byte copies, which are not guarded' \
            'makes that unlikely, not impossible' 'Remove the directory (`rm -rf <snapdir>`) after the last `verify` or `restore`' \
            'run `mktemp -d`, note the absolute path it prints' 'a shell variable may not survive between tool calls'; do
    [ "$(tr '\n' ' ' < "$1" | tr -s ' ' | grep -oF -- "$_p" | wc -l | tr -d ' ')" -ge 2 ] \
      || { echo "the emitters do not both carry: $_p"; return 1; }
  done
  [ "$(cnt 'is an accepted, unguarded gap' "$1")" -ge 1 ] || { echo "the /sdd-plan emitter does not state the unguarded board gap"; return 1; }
  if grep -qF '$snapdir' "$1"; then echo 'the shell-variable form $snapdir is back'; return 1; fi
  grep -qF 'tools/critic-guard.sh' "$1" || { echo "installer never names tools/critic-guard.sh"; return 1; }
  grep -qF 'chmod +x "$H/tools/critic-guard.sh"' "$1" || { echo "installer lacks the critic-guard executable wiring"; return 1; }
  grep -qE 'only file you may write is your note' "$1" || { echo "the doc-critic shim does not state its single write destination"; return 1; }
  return 0
}
expect_ok "E1" check_installer "$INST"
# one mutant per rule, applied to ONE emitter's copy only: the count rule must then red (the other emitter alone is not enough)
_im=0
for _pair in 'verify <snapdir>/plan-output.snap|verify "$snapdir/plan-output.snap"' \
             'run `mktemp -d`, note the absolute path it prints|run `mktemp -d` once' \
             'makes that unlikely, not impossible|makes that impossible' \
             'Remove the directory (`rm -rf <snapdir>`) after the last|Leave the directory after the last' \
             'do not continue until the file is confirmed|do not wait' \
             'If `restore` exits non-zero|If `restore` exits zero' \
             'unless the critic also rewrote the snapshot or its byte copies, which are not guarded|always'; do
  _im=$((_im + 1))
  python3 -I - "$INST" "$T/inst-$_im.sh" "${_pair%%|*}" "${_pair#*|}" <<'PY' || fail "installer mutant $_im: pattern not found"
import sys
src, out, a, b = sys.argv[1:5]
t = " ".join(open(src).read().split()) if False else open(src).read()
import re
pat = re.sub(r"\\ +", " ", re.escape(a)).replace(r"\ ", r"\s+")
n, k = re.subn(pat, lambda m: b, t, count=1)
if k != 1:
    sys.exit(1)
open(out, "w").write(n)
PY
  expect_bad "E1 installer mutant $_im" check_installer "$T/inst-$_im.sh"
done
pass "E1: installer emitters each carry the guard rules (7 one-emitter mutants rejected) and the shim states the single write destination"

pass "all critic-guard rows passed"
