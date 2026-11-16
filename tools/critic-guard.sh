#!/bin/sh
# critic-guard.sh — prove the doc-critic left the documents it reviewed untouched, and put them
# back when it did not (E99-F186).
#
# The Doc-critic is advisory: it may write only its note (agents/doc-critic.md), but the Write
# tool it is granted does not confine the destination, so a spawned critic can overwrite a
# reviewed file (GitHub #323). The generating agent snapshots the reviewed files before the
# spawn, verifies them right after it returns, and restores them from the snapshot's byte copies.
#
# Usage:
#   critic-guard.sh snapshot <name>.snap <file>...   record `cksum` of each file and keep a byte copy
#   critic-guard.sh verify   <name>.snap             recompute and compare
#   critic-guard.sh restore  <name>.snap             copy back each changed or missing file, then verify
#
# The snapshot path MUST end in `.snap`, must not be one of the listed files (nor the same file
# by link) and must not be a directory: snapshot refuses with exit 2 before writing anything, so
# a forgotten snapshot argument can never overwrite a reviewed file. The byte copies live in
# `<name>.snap.d/`, one numbered copy per snapshot line. snapshot creates the snapshot file's
# parent directory if needed and writes nothing when any <file> is unreadable.
#
# Output (stdout) of verify (and the last lines of restore): one line per differing file, then
# one summary line.
#   CHANGED | <path>     the file's checksum or size differs from the snapshot
#   MISSING | <path>     the file no longer exists or is unreadable
#   critic-guard: <N> files unchanged                  (exit 0)
#   critic-guard: <C> of <N> reviewed files changed    (exit 1; a MISSING or UNRESTORABLE file counts)
# restore prints `RESTORED | <path>` for each file it copied back, before the verify output. It
# checksums a byte copy against the checksum recorded in the snapshot BEFORE copying it; a file whose
# copy is gone or does not match is left untouched and reported `UNRESTORABLE | <path>` (counted as
# changed, exit 1).
#
# Exit codes: 0 every file matches the checksum recorded in the snapshot (after the restore, for restore)
#             1 at least one file changed or missing (after the restore, for restore)
#             2 usage error, or the snapshot could not be taken or read (reason on stderr)
#
# Known limits (the prose must never over-claim): the checksum is POSIX `cksum` (CRC-32 plus
# size) — it catches an accidental or model-made rewrite, not a deliberate collision; only the
# files named at snapshot time are watched, so a file the critic CREATES is not seen; paths
# containing whitespace are refused; paths are recorded as given, so run verify and restore from
# the working directory that took the snapshot (or pass absolute paths); the snapshot and its
# `.d/` copies are themselves writable by the critic and are not guarded.

set -eu
LC_ALL=C
export LC_ALL

usage_err() { printf 'critic-guard: %s\n' "$1" >&2; exit 2; }

# scan <snap> <restore:0|1> — walk the snapshot; print RESTORED/CHANGED/MISSING; set total, bad.
scan() {
  _snap="$1"; _restore="$2"; total=0; bad=0; _n=0
  [ -f "$_snap" ] && [ -r "$_snap" ] || usage_err "no readable snapshot: $_snap"
  while read -r crc size f || [ -n "${crc:-}" ]; do
    case "$crc" in ''|*[!0-9]*) usage_err "malformed snapshot line in $_snap" ;; esac
    case "$size" in ''|*[!0-9]*) usage_err "malformed snapshot line in $_snap" ;; esac
    case "$f" in ''|*[[:space:]]*) usage_err "malformed snapshot line in $_snap" ;; esac
    _n=$((_n + 1)); total=$((total + 1))
    now=""
    [ -f "$f" ] && [ -r "$f" ] && now="$(cksum < "$f")" || now=""
    _lost=0
    if [ "$now" != "$crc $size" ] && [ "$_restore" = 1 ]; then
      # Check the byte copy against the recorded checksum BEFORE it touches the reviewed file.
      _cp=""
      [ -f "$_snap.d/$_n" ] && [ -r "$_snap.d/$_n" ] && _cp="$(cksum < "$_snap.d/$_n")" || _cp=""
      if [ "$_cp" = "$crc $size" ]; then
        mkdir -p -- "$(dirname -- "$f")" 2>/dev/null || true
        if cp -- "$_snap.d/$_n" "$f" 2>/dev/null; then
          printf 'RESTORED | %s\n' "$f"
          now="$(cksum < "$f")" || now=""
        fi
      else
        printf 'UNRESTORABLE | %s\n' "$f"; _lost=1; bad=$((bad + 1))
      fi
    fi
    if [ "$_lost" = 1 ]; then
      :
    elif [ ! -f "$f" ] || [ ! -r "$f" ]; then
      printf 'MISSING | %s\n' "$f"; bad=$((bad + 1))
    elif [ "$now" != "$crc $size" ]; then
      printf 'CHANGED | %s\n' "$f"; bad=$((bad + 1))
    fi
  done < "$_snap"
  [ "$total" -gt 0 ] || usage_err "empty snapshot: $_snap"
  if [ "$bad" -gt 0 ]; then
    printf 'critic-guard: %s of %s reviewed files changed\n' "$bad" "$total"
    return 1
  fi
  printf 'critic-guard: %s files unchanged\n' "$total"
}

mode="${1:-}"
case "$mode" in
  snapshot)
    [ "$#" -ge 3 ] || usage_err "usage: critic-guard.sh snapshot <name>.snap <file>..."
    snap="$2"; shift 2
    case "$snap" in *.snap) ;; *) usage_err "the snapshot path must end in .snap (is the first argument the snapshot file?): $snap" ;; esac
    [ ! -d "$snap" ] || usage_err "the snapshot path is a directory: $snap"
    for f in "$@"; do
      case "$f" in *[[:space:]]*) usage_err "path contains whitespace (unsupported): $f" ;; esac
      [ -f "$f" ] && [ -r "$f" ] || usage_err "not a readable file: $f"
      if [ -e "$snap" ] && [ "$f" -ef "$snap" ]; then usage_err "the snapshot path is the same file as listed file $f"; fi
    done
    stage="$(mktemp -d 2>/dev/null || mktemp -d -t criticguard)" || usage_err "cannot create a temporary directory"
    trap 'rm -rf "$stage"' EXIT
    n=0
    for f in "$@"; do
      n=$((n + 1))
      sum="$(cksum < "$f")" || usage_err "cannot checksum: $f"
      cp -- "$f" "$stage/$n" || usage_err "cannot copy: $f"
      printf '%s %s\n' "$sum" "$f" >> "$stage/snap"
    done
    mkdir -p -- "$(dirname -- "$snap")" 2>/dev/null || usage_err "cannot create directory for: $snap"
    rm -rf -- "$snap.d"
    mkdir -- "$snap.d" 2>/dev/null || usage_err "cannot create: $snap.d"
    i=1
    while [ "$i" -le "$n" ]; do
      cp -- "$stage/$i" "$snap.d/$i" || usage_err "cannot write a byte copy in $snap.d"
      i=$((i + 1))
    done
    cp -- "$stage/snap" "$snap" 2>/dev/null || usage_err "cannot write snapshot: $snap"
    ;;
  verify)
    [ "$#" -eq 2 ] || usage_err "usage: critic-guard.sh verify <name>.snap"
    scan "$2" 0 || exit 1
    ;;
  restore)
    [ "$#" -eq 2 ] || usage_err "usage: critic-guard.sh restore <name>.snap"
    scan "$2" 1 || exit 1
    ;;
  *) usage_err "usage: critic-guard.sh <snapshot|verify|restore> ..." ;;
esac
