#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "$0")/.." && pwd)"
work="$(mktemp -d)"
sleep 300 &
owner=$!
trap 'kill "$owner" 2>/dev/null || true; rm -rf -- "$work"' EXIT
export XDG_RUNTIME_DIR="$work"
mkdir "$work/hxp"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

started() {
  local stat; stat="$(<"/proc/$1/stat")"; stat="${stat##*) }"
  # shellcheck disable=SC2086
  set -- $stat
  printf '%s' "${20}"
}
socket() { python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }
true & dead=$!
wait "$dead"
socket "$work/live.sock"

state() {  # name, then lines
  local name=$1; shift
  printf '%s\n' "$@" >"$work/hxp/$name.state"
}
start="$(started "$owner")"
state live "src=/docs/a b.typ" editor=helix "tmux=/tmp/tmux-1000/default,42,0" tmux_pane=%3 \
  "pid=$owner" "pid_start=$start" "viewer_socket=$work/live.sock" viewer=fancy-cat
state older src=/docs/c.md editor=micro "pid=$owner" viewer=zathura "viewer_socket=$work/ignored"
state dead src=/docs/d.md editor=helix "pid=$dead" viewer=zathura
state reused src=/docs/e.md editor=helix "pid=$owner" pid_start=1 viewer=zathura
state nosocket src=/docs/f.md editor=helix "pid=$owner" "pid_start=$start" \
  "viewer_socket=$work/gone.sock" viewer=fancy-cat
state tab "src=/docs/g	h.md" editor=helix "pid=$owner" viewer=zathura

expected="$(printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  /tmp/tmux-1000/default %3 helix fancy-cat "$work/live.sock" '/docs/a b.typ' \
  '' '' micro zathura '' /docs/c.md | LC_ALL=C sort)"
actual="$("$repo/bin/hxp-sessions" | LC_ALL=C sort)"
[[ "$actual" == "$expected" ]] || fail "hxp-sessions listed:
$actual
expected:
$expected"
[[ -e "$work/hxp/dead.state" ]] || fail 'hxp-sessions deleted a state file'

rm -f "$work"/hxp/*.state
[[ -z "$("$repo/bin/hxp-sessions")" ]] || fail 'no sessions should print nothing'

echo 'PASS: hxp-sessions lists live sessions only'
