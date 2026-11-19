#!/bin/sh
# test_install_agent_selected.sh — E99-F191: harness-install.sh's agent_selected answers by a pure
# shell match, never through a subprocess. A crashed `grep` there (a "Segmentation fault: 11"
# under load) once answered differently for the same key within one run, so
# skill_unit_claimed was false while `agent_selected pi` was true and the install aborted on
# an unset `_cdx_cmds`. The REAL function is extracted from the installer and exercised:
# exact whole-line matching over the newline-separated $SELECTED. A substring-matching mutant
# and a reintroduced subprocess are both rejected.
# Constraints: reads only; everything under $T.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t agentsel)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# extract <installer> <out> — the top-level agent_selected() definition, verbatim
extract() {
  awk '/^agent_selected\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' "$1" > "$2"
  [ -s "$2" ] || return 1
}

# check <fn-file> — 0 when the function matches exactly, in-process. Prints the first failure.
check() {
  if sed 's/#.*//' "$1" | grep -qE '(^|[^_a-z])(grep|awk|sed|printf[^;]*\|)'; then
    echo "agent_selected runs a subprocess or pipe"; return 1
  fi
  sh -c '
    set -eu
    . "$1"
    t() { # <selected-lines> <key> <want 0|1>
      SELECTED="$1"
      if agent_selected "$2"; then got=0; else got=1; fi
      [ "$got" = "$3" ] || { echo "SELECTED=[$1] key=[$2]: got $got, want $3"; exit 1; }
    }
    nl="
"
    t "claude${nl}codex${nl}pi" codex 0
    t "claude${nl}codex${nl}pi" claude 0
    t "claude${nl}codex${nl}pi" pi 0
    t "claude${nl}codex${nl}pi" opencode 1
    t "claude${nl}codex${nl}pi" code 1
    t "claude${nl}codex${nl}pi" "" 1
    t "codex" codex 0
    t "codex" c.dex 1
    t "" claude 1
    t "antigravity" anti 1
  ' sh "$1"
}

extract "$SRC/harness-install.sh" "$T/fn.sh" || fail "no top-level agent_selected() in harness-install.sh"
_o="$(check "$T/fn.sh")" || fail "agent_selected: $_o"
pass "agent_selected_exact_and_in_process"

# mutant 1: a substring match must be rejected ("code" would select codex)
cat > "$T/m1.sh" <<'M'
agent_selected() {
  case "$SELECTED" in *"$1"*) return 0 ;; esac
  return 1
}
M
if check "$T/m1.sh" >/dev/null; then fail "a substring-matching agent_selected was not rejected"; fi
# mutant 2: the old subprocess form must be rejected even though it matches correctly
cat > "$T/m2.sh" <<'M'
agent_selected() {
  printf '%s\n' "$SELECTED" | grep -qx "$1"
}
M
if check "$T/m2.sh" >/dev/null; then fail "a subprocess-based agent_selected was not rejected"; fi
pass "agent_selected_mutants_rejected (substring, subprocess)"

echo "all agent_selected checks passed"
