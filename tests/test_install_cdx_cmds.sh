#!/bin/sh
# test_install_cdx_cmds.sh — E99-F191: harness-install.sh computes the shared-skill command list
# `_cdx_cmds` OUTSIDE the `if skill_unit_claimed; then` block. The pi template block after it
# reads `_cdx_cmds` on the assumption that pi selected implies skill_unit_claimed. A crashed
# `grep` inside agent_selected (a "Segmentation fault: 11" under load) once made
# skill_unit_claimed false while `agent_selected pi` stayed true, and `set -u` aborted the
# install with "_cdx_cmds: parameter not set". A structural pin, because that crash cannot be
# reproduced on demand: the assignment must sit before the block, at the block's own indent.
# Constraints: reads only.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t cdxcmds)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# check <installer> — 0 when the first `_cdx_cmds=` assignment precedes the
# `if skill_unit_claimed; then` that opens the shared skill-unit block, at the same indent.
check() {
  awk '
    /^[ ]*_cdx_cmds="\$HARNESS_EMITTED_CMDS"/ && !assign { assign = NR; match($0, /^[ ]*/); ai = RLENGTH }
    /^[ ]*if skill_unit_claimed; then/ && !block { block = NR; match($0, /^[ ]*/); bi = RLENGTH }
    END {
      if (!assign) { print "no _cdx_cmds assignment"; exit 1 }
      if (!block)  { print "no skill_unit_claimed block"; exit 1 }
      if (assign > block) { print "_cdx_cmds is assigned inside or after the skill_unit_claimed block (line " assign " > " block ")"; exit 1 }
      if (ai != bi) { print "_cdx_cmds is not assigned at the block indent"; exit 1 }
    }' "$1"
}

_o="$(check "$SRC/harness-install.sh")" || fail "$_o"
pass "cdx_cmds_assigned_outside_skill_unit_block"

# mutant: the pre-fix shape (assignment moved back inside the block) must be rejected
awk '
  /^[ ]*_cdx_cmds="\$HARNESS_EMITTED_CMDS"/ && !held { held = $0; next }
  /^[ ]*if pr_loop_enabled; then _cdx_cmds=/ && !held2 { held2 = $0; next }
  { print }
  /^[ ]*if skill_unit_claimed; then/ && held && !done { print "    " held; print "    " held2; done = 1 }
' "$SRC/harness-install.sh" > "$T/mut.sh"
cmp -s "$SRC/harness-install.sh" "$T/mut.sh" && fail "setup: the mutant did not apply"
if check "$T/mut.sh" >/dev/null; then fail "the pre-fix shape (assignment inside the block) was not rejected"; fi
pass "cdx_cmds_inside_block_mutant_rejected"

echo "all _cdx_cmds checks passed"
