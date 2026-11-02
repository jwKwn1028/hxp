#!/usr/bin/env zsh
# Session regressions without compilers, editors, viewers, or an X server.
emulate -L zsh
set -u

repo="${0:A:h:h}"
source "$repo/zsh/hxp-main.zsh"
# Use this checkout's library.
source "$repo/zsh/hxp-lib.zsh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
typeset -g fail=0

check() {
  if [[ "$2" == "$3" ]]; then
    print -r -- "    ✓ $1"
  else
    print -r -- "    ✗ $1: expected [$2] got [$3]"
    fail=1
  fi
}

print -r -- '  [scaffolding]'
saved_path="$PATH"
for ext in md tex typ; do
  target="$work/new $ext/nested/document.$ext"
  _hxp_scaffold "$target"
  check "$ext creates missing parents" 0 "$?"
  check "$ext has starter content" yes "$([[ -s "$target" ]] && print yes)"
done
check 'scaffolding preserves PATH' "$saved_path" "$PATH"

project="$work/project with spaces"
mkdir -p "$project/chapters"
print -rl -- '\documentclass{article}' '\begin{document}' '\input{chapters/intro}' '\end{document}' > "$project/main.tex"
print -r -- 'Chapter text.' > "$project/chapters/intro.tex"
print -rl -- '= Root' '#include "chapters/intro.typ"' > "$project/main.typ"
print -r -- 'Chapter text.' > "$project/chapters/intro.typ"
print -r -- '# Notes' > "$project/notes.md"

print -r -- '  [watcher output paths]'
(
  _hxp_need_cmd() { return 0 }
  _hxp_compile_once() { print -r -- "$5" >> "$work/compile-targets" }
  _hxp_sweep_artifacts() { print -r -- "$5" > "$work/swept-sidecar" }
  watchexec() {
    while [[ "$1" != -- ]]; do shift; done
    shift 2 # -- hxp-compile
    _hxp_compile_once "$@"
  }
  inotifywait() { print -r -- "$test_src" }
  typst() { print -r -- "${@[-1]}" > "$work/watch-target" }
  _hxp_typst_watch_render() {
    cat >/dev/null
    print -r -- "$7" > "$work/render-target"
    print -r -- "$8" > "$work/render-watch-target"
  }

  for ext in md tex typ; do
    test_src="$project/chapters/intro.$ext"
    expected="$project/main.pdf"
    if [[ "$ext" == md ]]; then
      test_src="$project/notes.md"
      expected="$project/notes.pdf"
    fi
    : > "$work/compile-targets"
    HXP_NO_NATIVE_TYP=1 HXP_NO_WATCHEXEC=0 wpdf -q "$test_src"
    check "$ext initial and watchexec outputs agree" "$expected"$'\n'"$expected" "$(cat "$work/compile-targets")"
    check "$ext sweeps the PDF sidecar" "${expected:r}.synctex.gz" "$(cat "$work/swept-sidecar")"

    : > "$work/compile-targets"
    HXP_NO_NATIVE_TYP=1 HXP_NO_WATCHEXEC=1 wpdf -q --no-initial "$test_src"
    check "$ext inotify output" "$expected" "$(cat "$work/compile-targets")"
  done
  HXP_NO_NATIVE_TYP=0 wpdf -q --no-initial "$project/chapters/intro.typ"
  check 'native typst writes a private staging PDF' "$project/chapters/.intro.tmp.watch.pdf" "$(cat "$work/watch-target")"
  check 'native typst renderer reads the staging PDF' "$(cat "$work/watch-target")" "$(cat "$work/render-watch-target")"
  check 'native typst error output' "$project/main.pdf" "$(cat "$work/render-target")"
  exit "$fail"
) || fail=1

print -r -- '  [viewer ownership]'
(
  wmctrl() { cat "$work/windows" }
  cat > "$work/windows" <<'EOF'
0x001 0 111 sioyek.Sioyek host main.pdf
0x002 0 111 sioyek.Sioyek host main.pdf
0x003 0 222 terminal.Terminal host main.pdf
EOF
  check 'only claims the newly created viewer' 0x002 "$(_hxp_find_viewer_window sioyek 999 /b/main.pdf 0x001)"
  check 'shared PID cannot disambiguate new windows' '' "$(_hxp_find_viewer_window sioyek 111 /b/main.pdf '')"
  check 'never claims an existing window' '' "$(_hxp_find_viewer_window sioyek 111 /b/main.pdf $'0x001\n0x002')"
  HXP_NO_TILE=1
  HXP_WM=tiling
  check 'ownership tracking works without tiling' 0x002 "$(_hxp_wait_for_viewer_window sioyek 999 /b/main.pdf 0x001)"

  cat > "$work/windows" <<'EOF'
0x001 0 111 org.pwmt.zathura.Zathura host main.pdf
0x002 0 222 org.pwmt.zathura.Zathura host Document title
0x003 0 333 org.pwmt.zathura.Zathura host main.pdf
EOF
  check 'zathura ownership follows its process, even with a custom title' 0x002 "$(_hxp_find_viewer_window zathura 222 /b/main.pdf 0x001)"
  check 'zathura never claims a different newly opened process' '' "$(_hxp_find_viewer_window zathura 999 /b/main.pdf $'0x001\n0x002')"

  wmctrl() { print -r -- "$*" >> "$work/close-actions" }
  kill() { print -r -- "kill $*" >> "$work/close-actions" }
  : > "$work/close-actions"
  _hxp_close_viewer sioyek 111 0x002
  check 'closes the recorded window' '-ic 0x002' "$(cat "$work/close-actions")"
  : > "$work/close-actions"
  _hxp_close_viewer sioyek 111 ''
  check 'untracked shared viewer is left open' '' "$(cat "$work/close-actions")"
  wmctrl() { return 1 }
  _hxp_close_viewer sioyek 111 0x002
  check 'failed close never kills shared process' '' "$(cat "$work/close-actions")"
  _hxp_close_viewer zathura 222 ''
  check 'dedicated viewer retains PID fallback' 'kill -TERM 222' "$(cat "$work/close-actions")"
  exit "$fail"
) || fail=1

print -r -- '  [hxp session wiring]'
(
  export XDG_RUNTIME_DIR="$work/session-runtime" HXP_NO_TILE=1
  _hxp_need_cmd() { return 0 }
  _hxp_viewer() { print sioyek }
  _hxp_editor_window_id() { print 0xeee }
  _hxp_wmctrl_tile() { return 0 }
  _hxp_compile_once() { print -r -- "$5" > "$work/initial-pdf" }
  wpdf() { return 0 }
  pkill() { return 0 }
  kill() { return 0 }
  sioyek() {
    if [[ "$1" == --new-window ]]; then
      zmodload zsh/system
      print -r -- "$sysparams[pid]" > "$work/launch-pid"
    fi
  }
  wmctrl() {
    case "$1" in
      -l) print -r -- '0x001 0 host main.pdf' ;;
      -lpx)
        print -r -- '0x001 0 111 sioyek.Sioyek host main.pdf'
        [[ -s "$work/launch-pid" ]] && print -r -- '0x002 0 111 sioyek.Sioyek host main.pdf'
        [[ -f "$work/session-state" ]] && print -r -- '0x003 0 111 sioyek.Sioyek host main.pdf'
        ;;
      -ic) print -r -- "$2" > "$work/closed-window" ;;
    esac
  }
  _hxp_editor_open() {
    cp -- "$state_file" "$work/session-state"
    print -r -- "$zpid" > "$work/session-viewer-pid"
  }
  hxp "$project/chapters/intro.typ"
  check 'session initially compiles root PDF' "$project/main.pdf" "$(cat "$work/initial-pdf")"
  check 'records new window in state' viewer_windowid=0x002 "$(grep '^viewer_windowid=' "$work/session-state")"
  check 'captures viewer PID before toggle helper' "$(cat "$work/launch-pid")" "$(cat "$work/session-viewer-pid")"
  check 'persists viewer PID separately from session PID' "viewer_pid=$(cat "$work/launch-pid")" "$(grep '^viewer_pid=' "$work/session-state")"
  check 'cleanup keeps its original window identity' 0x002 "$(cat "$work/closed-window")"
  exit "$fail"
) || fail=1

print -r -- '  [zathura session with the same PDF already open]'
(
  export XDG_RUNTIME_DIR="$work/zathura-runtime" HXP_NO_TILE=1
  _hxp_need_cmd() { return 0 }
  _hxp_viewer() { print zathura }
  _hxp_editor_window_id() { print 0xeee }
  _hxp_wmctrl_tile() { return 0 }
  _hxp_compile_once() { return 0 }
  wpdf() { return 0 }
  pkill() { return 0 }
  kill() { print -r -- "$*" >> "$work/zathura-kills" }
  zathura() {
    zmodload zsh/system
    print -r -- "$sysparams[pid]" > "$work/zathura-launch-pid"
    print -r -- "$*" > "$work/zathura-launch-args"
  }
  wmctrl() {
    case "$1" in
      -l) print -r -- '0x001 0 host main.pdf' ;;
      -lpx)
        print -r -- '0x001 0 111 org.pwmt.zathura.Zathura host main.pdf'
        [[ -s "$work/zathura-launch-pid" ]] && print -r -- "0x002 0 $(cat "$work/zathura-launch-pid") org.pwmt.zathura.Zathura host main.pdf"
        ;;
      -ic) print -r -- "$2" > "$work/zathura-closed-window" ;;
    esac
  }
  _hxp_editor_open() { cp -- "$state_file" "$work/zathura-state" }
  hxp "$project/main.tex"
  check 'zathura launches a dedicated preview' "$project/main.pdf" "$(cat "$work/zathura-launch-args")"
  check 'zathura records its own process' "viewer_pid=$(cat "$work/zathura-launch-pid")" "$(grep '^viewer_pid=' "$work/zathura-state")"
  check 'zathura records its own window' viewer_windowid=0x002 "$(grep '^viewer_windowid=' "$work/zathura-state")"
  check 'zathura cleanup closes only its own window' 0x002 "$(cat "$work/zathura-closed-window")"
  exit "$fail"
) || fail=1

print -r -- '  [simultaneous viewer launches]'
(
  export XDG_RUNTIME_DIR="$work/parallel-runtime" HXP_NO_TILE=1
  mkdir -p "$work/a" "$work/b"
  print -r -- '\documentclass{article}' > "$work/a/main.tex"
  print -r -- '\documentclass{article}' > "$work/b/main.tex"
  _hxp_need_cmd() { return 0 }
  _hxp_viewer() { print sioyek }
  _hxp_editor_window_id() { print 0xeee }
  _hxp_wmctrl_tile() { return 0 }
  _hxp_compile_once() { return 0 }
  wpdf() { return 0 }
  pkill() { return 0 }
  kill() { return 0 }
  sioyek() {
    [[ "$1" == --new-window ]] || return 0
    local name="${${2:h}:t}"
    if [[ "$name" == a ]]; then
      : > "$work/a-launching"
      sleep 0.2 # B would appear first without launch serialization.
    fi
    : > "$work/$name-visible"
  }
  wmctrl() {
    case "$1" in
      -l|-lpx)
        [[ -f "$work/a-visible" ]] && print -r -- '0x00a 0 111 sioyek.Sioyek host main.pdf'
        [[ -f "$work/b-visible" ]] && print -r -- '0x00b 0 111 sioyek.Sioyek host main.pdf'
        ;;
    esac
    return 0
  }
  _hxp_editor_open() {
    cp -- "$state_file" "$work/${${src:h}:t}-state"
  }
  hxp "$work/a/main.tex" &
  a_pid=$!
  for attempt in {1..100}; do
    [[ -f "$work/a-launching" ]] && break
    sleep 0.01
  done
  hxp "$work/b/main.tex" &
  b_pid=$!
  wait "$a_pid" "$b_pid"
  check 'first launch owns its delayed window' viewer_windowid=0x00a "$(grep '^viewer_windowid=' "$work/a-state")"
  check 'second launch owns its own window' viewer_windowid=0x00b "$(grep '^viewer_windowid=' "$work/b-state")"
  exit "$fail"
) || fail=1

print -r -- '  [zathura forward search process selection]'
(
  export XDG_RUNTIME_DIR="$work/zathura-fwd-runtime"
  export HXP_TEST_WINDOWS="$work/zathura-fwd-windows" HXP_TEST_RAISED="$work/zathura-raised"
  export HXP_TEST_VIEWER_ARGS="$work/zathura-fwd-args" HXP_TEST_DBUS_CALLS="$work/dbus-calls"
  export HXP_TEST_PAGE_TARGET="$work/page-target" HXP_TEST_PDF="$project/main.pdf"
  export HXP_TEST_VIEWER_GONE=0
  mkdir -p "$work/bin"
  : > "$project/main.pdf"
  cat > "$work/bin/wmctrl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -lx) cat "$HXP_TEST_WINDOWS" ;;
  -i) printf '%s\n' "$3" > "$HXP_TEST_RAISED" ;;
esac
EOF
  cat > "$work/bin/zathura" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HXP_TEST_VIEWER_ARGS"
EOF
  cat > "$work/bin/gdbus" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HXP_TEST_DBUS_CALLS"
dest=''; method=''; last="${!#}"
while (( $# )); do
  case "$1" in
    --dest) dest="$2"; shift ;;
    --method) method="$2"; shift ;;
  esac
  shift
done
if [[ "$dest" == org.pwmt.zathura.PID-222 && "$HXP_TEST_VIEWER_GONE" == 1 ]]; then
  exit 1
fi
case "$method" in
  org.freedesktop.DBus.ListNames)
    printf "(['org.pwmt.zathura.PID-111', 'org.pwmt.zathura.PID-222'],)\n" ;;
  org.freedesktop.DBus.Properties.Get) printf "(<'%s'>,)\n" "$HXP_TEST_PDF" ;;
  org.pwmt.zathura.GotoPage)
    printf '%s %s\n' "$dest" "$last" > "$HXP_TEST_PAGE_TARGET"
    printf '(true,)\n' ;;
esac
EOF
  cat > "$work/bin/pdftotext" <<'EOF'
#!/usr/bin/env bash
printf 'First page.\fChapter text.\f'
EOF
  cat > "$work/bin/hxp-typtext" <<'EOF'
#!/usr/bin/env bash
printf 'Chapter text.\n'
EOF
  chmod +x "$work/bin/wmctrl" "$work/bin/zathura" "$work/bin/gdbus" "$work/bin/pdftotext" "$work/bin/hxp-typtext"
  export PATH="$work/bin:$PATH"
  cat > "$HXP_TEST_WINDOWS" <<'EOF'
0x001 0 org.pwmt.zathura.Zathura host main.pdf
0x002 0 org.pwmt.zathura.Zathura host main.pdf
EOF
  sf="$(_hxp_state_file "$project/main.tex")"
  mkdir -p "${sf:h}"
  write_zathura_state() {
    print -rl -- "src=$1" "pdf=$project/main.pdf" viewer=zathura "pid=$$" "viewer_windowid=$2" "viewer_pid=$3" > "$(_hxp_state_file "$1")"
  }
  for owned in 0x002 ''; do
    write_zathura_state "$project/main.tex" "$owned" 222
    rm -f -- "$HXP_TEST_VIEWER_ARGS" "$HXP_TEST_RAISED"
    bash "$repo/bin/hxp-fwd" "$project/main.tex" 3
    for attempt in {1..100}; do
      [[ -s "$HXP_TEST_VIEWER_ARGS" ]] && break
      sleep 0.01
    done
    check "zathura SyncTeX pins the preview process (window=$owned)" $'--synctex-pid\n222' "$(grep -A1 '^--synctex-pid$' "$HXP_TEST_VIEWER_ARGS")"
  done

  for viewer_pid in '' 0 -1 invalid; do
    write_zathura_state "$project/main.tex" '' "$viewer_pid"
    rm -f -- "$HXP_TEST_VIEWER_ARGS"
    bash "$repo/bin/hxp-fwd" "$project/main.tex" 3 2> "$work/fwd-warning"
    check "unresolved zathura process ($viewer_pid) reports failure" 1 "$?"
    check "unresolved zathura process ($viewer_pid) never dispatches by filename" no "$([[ -e "$HXP_TEST_VIEWER_ARGS" ]] && print yes || print no)"
  done

  write_zathura_state "$project/chapters/intro.typ" '' 222
  rm -f -- "$HXP_TEST_PAGE_TARGET" "$HXP_TEST_DBUS_CALLS" "$HXP_TEST_VIEWER_ARGS"
  bash "$repo/bin/hxp-fwd" "$project/chapters/intro.typ" 1
  check 'typst pages only the owned zathura, even without X11' 'org.pwmt.zathura.PID-222 1' "$(cat "$HXP_TEST_PAGE_TARGET" 2>/dev/null)"
  check 'owned typst search never enumerates other zathura processes' '' "$(grep 'ListNames' "$HXP_TEST_DBUS_CALLS")"

  export HXP_TEST_VIEWER_GONE=1
  rm -f -- "$HXP_TEST_PAGE_TARGET" "$HXP_TEST_VIEWER_ARGS"
  bash "$repo/bin/hxp-fwd" "$project/chapters/intro.typ" 1 2> "$work/fwd-warning"
  check 'missing preview reports failure' 1 "$?"
  check 'missing preview never pages the external copy' no "$([[ -e "$HXP_TEST_PAGE_TARGET" ]] && print yes || print no)"
  check 'missing preview never spawns an untracked window' no "$([[ -e "$HXP_TEST_VIEWER_ARGS" ]] && print yes || print no)"
  exit "$fail"
) || fail=1

print -r -- '  [forward search window selection]'
(
  export XDG_RUNTIME_DIR="$work/fwd-runtime"
  export HXP_TEST_WINDOWS="$work/fwd-windows" HXP_TEST_RAISED="$work/raised" HXP_TEST_VIEWER_ARGS="$work/viewer-args"
  mkdir -p "$work/bin"
  cat > "$work/bin/wmctrl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -lx) cat "$HXP_TEST_WINDOWS" ;;
  -i) printf '%s\n' "$3" > "$HXP_TEST_RAISED" ;;
esac
EOF
  cat > "$work/bin/sioyek" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HXP_TEST_VIEWER_ARGS"
EOF
  chmod +x "$work/bin/wmctrl" "$work/bin/sioyek"
  export PATH="$work/bin:$PATH"
  sf="$(_hxp_state_file "$project/main.tex")"
  mkdir -p "${sf:h}"
  : > "$project/main.pdf"
  cat > "$HXP_TEST_WINDOWS" <<'EOF'
0x001 0 sioyek.Sioyek host main.pdf
0x002 0 sioyek.Sioyek host main.pdf
0x003 0 terminal.Terminal host main.pdf
EOF
  for owned in 0x002 0xdead '' legacy; do
    {
      print -rl -- "src=$project/main.tex" "pdf=$project/main.pdf" viewer=sioyek "pid=$$"
      [[ "$owned" != legacy ]] && print -r -- "viewer_windowid=$owned"
    } > "$sf"
    rm -f -- "$HXP_TEST_RAISED" "$HXP_TEST_VIEWER_ARGS"
    bash "$repo/bin/hxp-fwd" "$project/main.tex" 3
    for attempt in {1..100}; do
      [[ -s "$HXP_TEST_VIEWER_ARGS" ]] && break
      sleep 0.01
    done
    if [[ "$owned" == 0x002 ]]; then
      check 'forward search raises owned window' 0x002 "$(cat "$HXP_TEST_RAISED" 2>/dev/null)"
      check 'forward search reuses owned window' --reuse-window "$(head -1 "$HXP_TEST_VIEWER_ARGS" 2>/dev/null)"
    else
      check "unresolved window ($owned) never raises a neighbour" no "$([[ -e "$HXP_TEST_RAISED" ]] && print yes || print no)"
      check "unresolved window ($owned) opens separately" --new-window "$(head -1 "$HXP_TEST_VIEWER_ARGS" 2>/dev/null)"
    fi
  done
  exit "$fail"
) || fail=1

if (( fail == 0 )); then
  print -r -- 'WORKFLOW TESTS PASSED'
else
  print -r -- 'WORKFLOW TESTS FAILED'
fi
exit "$fail"
