#!/bin/sh
# test_install_no_bytecode.sh — E99-F189: the installer never copies Python bytecode
# (`__pycache__/`, `*.pyc`) from the source tree into an install. Bytecode is a runtime artefact
# of running tools/*.py locally; copying it shipped stale, machine-specific files and made
# test_frontend_retirement's idempotence check flaky whenever a concurrent suite rewrote
# tools/__pycache__ in the shared source tree between that test's two installs.
# Constraints: installs from an isolated COPY of the source (never the working tree); no exact
# VERSION literal; everything under $T.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t nobytecode)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM
export CODEX_HOME="$T/codex-home"
export HARNESS_SKIP_UPDATE_CHECK=1

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# an isolated source copy (the test_self_mode / test_feedback_config shape)
_fx="$T/src"; mkdir -p "$_fx"
for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.codex "$SRC"/.agents "$SRC"/.escalation-arming; do
  [ -e "$_e" ] || continue
  case "$(basename "$_e")" in .git|node_modules) continue ;; esac
  cp -R "$_e" "$_fx/" 2>/dev/null || true
done
# plant bytecode where a developer's local runs leave it, and a stray .pyc outside __pycache__
mkdir -p "$_fx/tools/__pycache__"
printf 'bytecode\n' > "$_fx/tools/__pycache__/tasks-lock.cpython-313.pyc"
printf 'bytecode\n' > "$_fx/agents/stray.pyc"

_tgt="$T/target"; mkdir -p "$_tgt"
git -C "$_tgt" init -q
_out="$T/install.out"
sh "$_fx/harness-install.sh" --agents=claude "$_tgt" > "$_out" 2>&1 \
  || { cat "$_out" >&2; fail "the install exited non-zero"; }

[ -f "$_tgt/.harness/tools/tasks-lock.py" ] || fail "the install is incomplete: .harness/tools/tasks-lock.py is missing"
_bc="$(find "$_tgt/.harness" \( -name __pycache__ -o -name '*.pyc' \) -print 2>/dev/null)"
[ -z "$_bc" ] || fail "Python bytecode was copied into the install: $_bc"
pass "install_copies_no_bytecode"

# a second install over the first stays bytecode-free too (the upgrade path uses the same copy)
sh "$_fx/harness-install.sh" "$_tgt" > "$_out" 2>&1 \
  || { cat "$_out" >&2; fail "the re-install exited non-zero"; }
_bc="$(find "$_tgt/.harness" \( -name __pycache__ -o -name '*.pyc' \) -print 2>/dev/null)"
[ -z "$_bc" ] || fail "Python bytecode was copied into the install on re-install: $_bc"
pass "reinstall_copies_no_bytecode"

echo "all no-bytecode checks passed"
