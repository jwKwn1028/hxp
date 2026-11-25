#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$repo/bin/hxp-resume"
HOOK="$repo/zsh/hxp-main.zsh"
if ! command -v tmux >/dev/null || ! command -v zsh >/dev/null; then
    echo 'SKIP: tmux and zsh are required'
    exit 0
fi

tmp="$(mktemp -d)"
sock="$tmp/tmux.sock"
trap 'tmux -S "$sock" kill-server 2>/dev/null || true; rm -rf "$tmp"' EXIT
unset TMUX TMUX_PANE
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
t() { tmux -S "$sock" "$@"; }
# shellcheck disable=SC2016  # Conditions are single-quoted for eval.
wait_for() {
    local _
    for _ in $(seq 50); do eval "$1" && return 0; sleep 0.1; done
    return 1
}

mkdir -p "$tmp/bin" "$tmp/doc dir"
printf '#!/bin/sh\n[ "$1" = --tmux-supported ] && [ -e "%s/client" ]\n' "$tmp" >"$tmp/bin/fancy-cat"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s|%%s\\n" "$HXP_RESUME" "$HXP_RESUME_EDITOR" "$PWD" "$*" >"%s/out"\nexec sleep 300\n' \
    "$tmp" >"$tmp/bin/shell"
chmod +x "$tmp/bin/fancy-cat" "$tmp/bin/shell"
src="$tmp/doc dir/it's.typ"
: >"$src"

t -f /dev/null new-session -d -s t -x 120 -y 30 -c "$tmp/doc dir" sh
t split-window -h -d -t t:0.0 sh
t set -g default-shell "$tmp/bin/shell"
t set -s @resurrect-restoring 1
quoted=$(printf '%s' "$src" | sed "s/'/'\\\\''/g")
t send-keys -t t:0.1 "PATH='$tmp/bin':\$PATH sh '$SCRIPT' 0 micro '$quoted'" Enter

panes() { t list-panes -t t:0 | wc -l; }
editor_id=$(t display -p -t t:0.0 '#{pane_id}')
wait_for '[ -n "$(t show -pqv -t t:0.1 @hxp-resume)" ]' || fail 'no @hxp-resume for a save while waiting'
[ "$(t show -pqv -t t:0.1 @hxp-resume)" = "$editor_id micro $src" ] ||
    fail "@hxp-resume: $(t show -pqv -t t:0.1 @hxp-resume)"
sleep 0.5
[ "$(panes)" = 2 ] || fail 'closed a pane before the restore finished'

t set -su @resurrect-restoring
wait_for 't capture-pane -p -t t:0.1 | grep -q "waiting for a Ghostty client"' || fail 'no waiting message'
[ "$(panes)" = 2 ] || fail 'reopened hxp before a client could draw fancy-cat'

: >"$tmp/client"
wait_for '[ "$(panes)" = 1 ] && [ -s "$tmp/out" ]' || fail "panes=$(panes), out=$(cat "$tmp/out" 2>/dev/null)"
[ "$(cat "$tmp/out")" = "$src|micro|$tmp/doc dir|-l" ] || fail "respawned with: $(cat "$tmp/out")"
t kill-server

for job in "bash -c 'read -r answer'" "set +m; sh -c 'read -r answer'"; do
    rm -f "$tmp/client" "$tmp/out"
    t -f /dev/null new-session -d -s b -x 120 -y 30 -c "$tmp/doc dir" sh
    t split-window -h -d -t b:0.0 sh
    t set -g default-shell "$tmp/bin/shell"
    t send-keys -t b:0.1 "PATH='$tmp/bin':\$PATH sh '$SCRIPT' 0 micro '$quoted'" Enter
    wait_for 't capture-pane -p -t b:0.1 | grep -q "waiting for a Ghostty client"' || fail "$job: no waiting message"
    shell=$(t display -p -t b:0.0 '#{pane_pid}')
    t send-keys -t b:0.0 "$job" Enter
    wait_for 'pgrep -P "$shell" >/dev/null' || fail "$job: the job did not start"
    : >"$tmp/client"
    wait_for 't capture-pane -p -t b:0.1 | grep -q "editor pane is busy"' ||
        fail "$job: hxp-resume did not leave the busy pane alone: $(t capture-pane -p -t b:0.1)"
    [ "$(t list-panes -t b:0 | wc -l)" = 2 ] && [ ! -e "$tmp/out" ] || fail "$job: the editor pane was replaced"
    pgrep -P "$shell" >/dev/null || fail "$job: the job was killed"
    [ -z "$(t show -pqv -t b:0.1 @hxp-resume)" ] || fail "$job: a save would still resume this window"
    t kill-server
done

mkdir -p "$tmp/home"
cat >"$tmp/home/.zshrc" <<EOF
source '$HOOK'
hxp() { print -r -- "\$*" >>'$tmp/hxp'; print -rl -- "\${(v)history[@]}" >'$tmp/history'; }
EOF
# Skip system zshrc to avoid interactive compinit checks.
t -f /dev/null new-session -d -s z -x 120 -y 30 -e "HXP_RESUME=$src" -e HXP_RESUME_EDITOR=micro \
    "env HOME='$tmp/home' ZDOTDIR='$tmp/home' zsh -d -i"
wait_for '[ -s "$tmp/hxp" ]' || fail "zsh did not run hxp; its pane shows:
$(t capture-pane -p -t z)"
t send-keys -t z 'true' Enter
sleep 0.3
[ "$(cat "$tmp/hxp")" = "--micro -- $src" ] || fail "hxp ran as: $(cat "$tmp/hxp")"
line=$(grep '^hxp ' "$tmp/history") || fail "no hxp in history: $(cat "$tmp/history")"
[ "$(zsh -fc 'eval "words=( $1 )"; print -rl -- $words' _ "$line")" = "$(printf 'hxp\n--micro\n--\n%s' "$src")" ] ||
    fail "history does not rerun the session: $line"

printf 'PASS: hxp-resume reopens the editor pane after restore and a client; zsh runs hxp once\n'
