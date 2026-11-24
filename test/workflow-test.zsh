#!/usr/bin/env zsh
# Session and build-option regressions.
emulate -L zsh
set -u

repo="${0:A:h:h}"
source "$repo/zsh/hxp-main.zsh"
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
    local direct=0
    while [[ "$1" != -- ]]; do [[ "$1" == (-n|--shell=none) ]] && direct=1; shift; done
    shift
    # Model watchexec shell joining without -n.
    (( direct )) || set -- ${(z)${(j: :)@}}
    shift # hxp-compile
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

print -r -- '  [real watchexec keeps paths whole]'
if (( $+commands[watchexec] && $+commands[inotifywait] && $+commands[pandoc] )); then
(
  wdir="$work/watch [dir] with spaces"
  mkdir -p "$wdir" "$work/wx-bin"
  print -r -- '# Doc' > "$wdir/doc.md"
  print -rl -- '#!/bin/sh' 'printf "%s\n" "$1" >> "$WX_ARGS"' > "$work/wx-bin/hxp-compile"
  chmod +x "$work/wx-bin/hxp-compile"
  export PATH="$work/wx-bin:$PATH" WX_ARGS="$work/wx-args" XDG_RUNTIME_DIR="$work/wx-runtime"
  wpdf -q --no-initial "$wdir/doc.md" >/dev/null 2>&1 &
  wpid=$!
  for attempt in {1..100}; do
    (( attempt % 10 == 1 )) && print -r -- "edit $attempt" >> "$wdir/doc.md"
    [[ -s "$WX_ARGS" ]] && break
    sleep 0.05
  done
  pkill -TERM -P "$wpid" 2>/dev/null; kill -TERM "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  check 'real watchexec passes the source path intact' "$wdir/doc.md" "$(head -1 "$WX_ARGS" 2>/dev/null)"
  exit "$fail"
) || fail=1
else
  print -r -- '    - skipped (needs watchexec, inotifywait and pandoc)'
fi

print -r -- '  [markdown build options]'
(
  mkdir -p "$work/md-options"
  print -rl -- '---' 'title: English' 'geometry: margin=1in' '---' 'Plain text — café ﬁ.' > "$work/md-options/en.md"
  print -rl -- '# 제목' '서로 다른 문장.' > "$work/md-options/ko.md"
  _hxp_md_declared_keys "$work/md-options/en.md" bibliography CJKmainfont geometry
  check 'one frontmatter pass finds the declared keys' geometry "${reply[*]}"
  check 'Latin text with accents and ligatures is not CJK' 1 "$(_hxp_has_cjk "$work/md-options/en.md"; print $?)"
  check 'Hangul is CJK' 0 "$(_hxp_has_cjk "$work/md-options/ko.md"; print $?)"
  export HXP_CJK_FONT_RESOLVED='Test CJK'
  _hxp_need_cmd() { [[ "$1" == (latexmk|xelatex) ]] }
  pandoc() { print -r -- "$*" > "$work/md-options/pandoc-args"; return 1 }
  _hxp_make_error_pdf() { return 1 }
  for doc in en ko; do
    d="$work/md-options"
    _hxp_compile_once "$d/$doc.md" md "$d" "$doc" "$d/$doc.pdf" "$d/.$doc.tmp.pdf" "$d/.$doc.error.log" \
      "$d/.$doc.error.md" "$d/.$doc.debug.tex" "$d/.hxp_build_$doc" >/dev/null
    cjk=no; [[ "$(<"$d/pandoc-args")" == *"CJKmainfont=Test CJK"* ]] && cjk=yes
    check "$doc build loads xeCJK only for CJK text" "$([[ $doc == ko ]] && print yes || print no)" "$cjk"
  done
  geometry=no; [[ "$(<"$work/md-options/pandoc-args")" == *"geometry=margin=0.75in"* ]] && geometry=yes
  check 'undeclared geometry gets the default margin' yes "$geometry"
  exit "$fail"
) || fail=1

print -r -- '  [CJK in configured bibliographies]'
if (( $+commands[pandoc] )); then
(
  # Test bundled filter lookup through the installed symlink.
  ln -s "$repo/zsh/hxp-lib.zsh" "$work/installed-lib.zsh"
  source "$work/installed-lib.zsh"
  d="$work/md-bibliographies"
  mkdir -p "$d/references with spaces"
  print -rl -- '@book{english,' '  author = {Smith, Alice},' '  title = {English title},' '  year = {2020}' '}' > "$d/english.bib"
  print -rl -- '@book{korean,' '  author = {Kim, Jisu},' '  title = {한국어 제목},' '  year = {2021}' '}' > "$d/references with spaces/korean.bib"
  export HXP_CJK_FONT_RESOLVED='Test CJK'
  unset HXP_CJK_FONT
  _hxp_need_cmd() { [[ "$1" == (latexmk|xelatex) ]] }
  # Generate TeX without invoking LaTeX.
  pandoc() { command pandoc "$@"; return 1 }
  _hxp_make_error_pdf() { return 1 }
  for form in scalar inline-list block-list english override; do
    {
      print -r -- '---'
      case "$form" in
        scalar) print -r -- 'bibliography: "references with spaces/korean.bib"' ;;
        inline-list) print -r -- "bibliography: [english.bib, 'references with spaces/korean.bib']" ;;
        block-list) print -rl -- 'bibliography:' '  - english.bib' "  - \"$d/references with spaces/korean.bib\"" ;;
        english) print -r -- 'bibliography: english.bib' ;;
        override) print -rl -- 'bibliography: "references with spaces/korean.bib"' 'CJKmainfont: Explicit CJK' ;;
      esac
      print -rl -- '---' 'An English document with a citation [@english; @korean].'
    } > "$d/$form.md"
    (cd /; _hxp_compile_once "$d/$form.md" md "$d" "$form" "$d/$form.pdf" "$d/.$form.tmp.pdf" \
      "$d/.$form.error.log" "$d/.$form.error.md" "$d/.$form.debug.tex" "$d/.hxp_build_$form") >/dev/null
    tex="$d/.hxp_build_$form/$form.hxp.tex"
    font=no; grep -qF 'Test CJK' "$tex" && font=yes
    expected=yes; [[ "$form" == (english|override) ]] && expected=no
    check "$form bibliography chooses the CJK default only when needed" "$expected" "$font"
    if [[ "$form" == override ]]; then
      check 'frontmatter CJK font is preserved' yes "$(grep -qF 'Explicit CJK' "$tex" && print yes || print no)"
    fi
  done
  exit "$fail"
) || fail=1
else
  print -r -- '    - skipped (needs pandoc)'
fi

print -r -- '  [concurrent error reports]'
(
  report_work="$work/concurrent-reports"
  mkdir -p "$report_work"
  export XDG_RUNTIME_DIR="$report_work/runtime"
  unset HXP_KEEP_LAST_GOOD
  _hxp_need_cmd() { [[ "$1" == typst ]] }
  pandoc() { return 1 }
  wait_reports() {
    local pattern="$1" attempt
    for attempt in {1..200}; do
      [[ -e "$report_work/a.$pattern" && -e "$report_work/b.$pattern" ]] && return 0
      sleep 0.01
    done
    return 1
  }
  _hxp_make_typst_report_pdf() {
    local parts="$1" output="$2" name="${2:t:r}"
    print -r -- "$parts" > "$report_work/$name.parts"
    stat -c %a -- "$parts" > "$report_work/$name.mode"
    : > "$report_work/$name.ready"
    wait_reports ready || return 1
    cat "$parts/primary.txt" "$parts/link.txt" > "$output" || return 1
    : > "$report_work/$name.read"
    # Finish both reads before cleanup.
    wait_reports read
  }
  for name in a b; do
    print -r -- "Source for $name" > "$report_work/$name.tex"
    print -r -- "$report_work/$name.tex:1: Error in $name." > "$report_work/$name.log"
  done
  _hxp_make_error_pdf "$report_work/a.tex" tex "$report_work/a.log" "$report_work/a.md" "$report_work/a.pdf" '' "$report_work/a.final.pdf" &
  a_pid=$!
  _hxp_make_error_pdf "$report_work/b.tex" tex "$report_work/b.log" "$report_work/b.md" "$report_work/b.pdf" '' "$report_work/b.final.pdf" &
  b_pid=$!
  wait "$a_pid"; check 'first concurrent report succeeds' 0 "$?"
  wait "$b_pid"; check 'second concurrent report succeeds' 0 "$?"
  for name in a b; do
    check "$name report retains its own error and source link" \
      "Error in $name."$'\n'"file://$report_work/$name.tex#1" "$(cat "$report_work/$name.pdf" 2>/dev/null)"
    check "$name report directory is private" 700 "$(cat "$report_work/$name.mode" 2>/dev/null)"
  done
  check 'concurrent reports use different directories' yes \
    "$([[ -s "$report_work/a.parts" && -s "$report_work/b.parts" && \
          "$(cat "$report_work/a.parts")" != "$(cat "$report_work/b.parts")" ]] && print yes || print no)"
  leftovers=( "$XDG_RUNTIME_DIR"/hxp/errdoc.*(N) )
  check 'report directories are cleaned up' 0 "${#leftovers}"
  exit "$fail"
) || fail=1

print -r -- '  [preview selection]'
(
  export TMUX='' TMUX_PANE='' TERM_PROGRAM=ghostty WINDOWID=42 DISPLAY=:1 GHOSTTY_SURFACE_ID=test
  export HXP_VIEWER=sioyek
  local installed=' fancy-cat zathura sioyek xdotool ' passthrough=1
  _hxp_need_cmd() { [[ "$installed" == *" $1 "* ]] }
  fancy-cat() {
    case "$1" in
      --help) print -r -- '--listen SOCKET --inverse-search-resolver PROGRAM' ;;
      --tmux-supported) (( passthrough )) ;;
    esac
  }
  check 'native split outranks the GUI preference' fancy-cat "$(_hxp_viewer)"
  fancy-cat() { [[ "$1" == --help ]] && print -r -- '--listen SOCKET' }
  check 'fork builds without the resolver still split' fancy-cat "$(_hxp_viewer)"
  fancy-cat() {
    case "$1" in
      --help) print -r -- '--listen SOCKET --inverse-search-resolver PROGRAM' ;;
      --tmux-supported) (( passthrough )) ;;
    esac
  }
  check 'HXP_NO_SPLIT=1 keeps the GUI viewer' sioyek "$(HXP_NO_SPLIT=1 _hxp_viewer)"
  check 'split check explains the opt-out' 'disabled by HXP_NO_SPLIT=1' "$(HXP_NO_SPLIT=1 _hxp_split_check)"
  installed=' fancy-cat zathura sioyek '
  check 'split check names a missing xdotool' 'Ghostty splits need xdotool' "$(_hxp_split_check)"
  installed=' fancy-cat zathura sioyek xdotool '
  TMUX=test TMUX_PANE=%1
  check 'graphics-capable tmux gets a split' fancy-cat "$(_hxp_viewer)"
  passthrough=0
  check 'unsupported tmux honors GUI fallback preference' sioyek "$(_hxp_viewer)"
  unset HXP_VIEWER
  installed=' zathura sioyek '
  check 'Zathura is the default GUI fallback' zathura "$(_hxp_viewer)"
  installed=' sioyek '
  check 'Sioyek alone remains usable' sioyek "$(_hxp_viewer)"
  installed=' '
  _hxp_viewer >/dev/null
  check 'no available viewer reports failure' 1 "$?"
  exit "$fail"
) || fail=1

print -r -- '  [preview session pin]'
(
  export XDG_RUNTIME_DIR="$work/launch-runtime" HXP_SESSION_SRC="$project/main.typ"
  mkdir -p "$XDG_RUNTIME_DIR"
  pdf="$project/main.pdf" preview_dir='' preview_pane='' preview_shell=''
  help='--listen SOCKET --inverse-search-resolver PROGRAM'
  fancy-cat() { [[ "$1" == --help ]] && print -r -- "$help" }
  tmux() { print -r -- "${(j:|:)@}" > "$work/split-args"; return 1 }
  TMUX=test TMUX_PANE=%1 _hxp_start_split
  check 'tmux preview receives the session pin and resolver' yes \
    "$([[ "$(<"$work/split-args")" == *"|-e|HXP_PREVIEW_SRC=$project/main.typ|fancy-cat|--listen|"*"|--inverse-search|hxp-jump|--inverse-search-resolver|hxp-inverse|$pdf" ]] && print yes || print no)"
  help='--listen SOCKET'
  TMUX=test TMUX_PANE=%1 _hxp_start_split
  check 'older fork builds launch without the resolver' yes \
    "$([[ "$(<"$work/split-args")" == *"|fancy-cat|--listen|"*"|--inverse-search|hxp-jump|$pdf" ]] && print yes || print no)"

  help='--listen SOCKET --inverse-search-resolver PROGRAM'
  xdotool() { [[ "$1" == getactivewindow ]] && print -r -- "$WINDOWID" || return 1 }
  TMUX='' WINDOWID=42 GHOSTTY_SURFACE_ID=editor _hxp_start_split
  check 'Ghostty request records the session source' "$project/main.typ" "$(cat "$preview_dir/src" 2>/dev/null)"
  check 'Ghostty request records resolver support' yes "$([[ -e "$preview_dir/resolver" ]] && print yes || print no)"

  claim_home="$work/claim-home" claim_bin="$work/claim-bin"
  mkdir -p "$claim_home/.zsh" "$claim_bin"
  ln -s "$repo/zsh/hxp-lib.zsh" "$claim_home/.zsh/hxp-lib.zsh"
  print -rl -- '#!/bin/sh' 'printf "%s\n" "pin=${HXP_PREVIEW_SRC:-}" "$@" > "$CLAIMED"' > "$claim_bin/fancy-cat"
  chmod +x "$claim_bin/fancy-cat"
  print -r -- other > "$preview_dir/source-surface"
  print -r -- "$$" > "$preview_dir/owner"
  ln -sfT -- "$preview_dir" "$XDG_RUNTIME_DIR/hxp-preview-$UID/window-42"
  env -i HOME="$claim_home" PATH="$claim_bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    CLAIMED="$work/claimed" TERM_PROGRAM=ghostty WINDOWID=42 GHOSTTY_SURFACE_ID=split \
    zsh -f -i -c "source ${(q)repo}/zsh/hxp-main.zsh" </dev/null >/dev/null 2>&1
  check 'claimed Ghostty preview exports the pin' "pin=$project/main.typ" "$(head -1 "$work/claimed" 2>/dev/null)"
  check 'claimed Ghostty preview uses the resolver' yes \
    "$(grep -qx -- --inverse-search-resolver "$work/claimed" 2>/dev/null && print yes || print no)"
  exit "$fail"
) || fail=1

print -r -- '  [hangup watchdog]'
if (( $+commands[script] && $+commands[python3] )); then
(
  wd="$work/watchdog"
  mkdir -p "$wd"
  # Model Helix ignoring SIGHUP.
  print -rl -- 'import os, signal, sys, time' 'signal.signal(signal.SIGHUP, signal.SIG_IGN)' \
    'open(sys.argv[1], "w").write(str(os.getpid()))' 'time.sleep(60)' > "$wd/editor.py"
  print -rl -- "source ${(q)repo}/zsh/hxp-main.zsh" 'zmodload zsh/system' "trap '' HUP" \
    'shell_pid=$sysparams[pid]' \
    "{ _hxp_hangup_watchdog \$shell_pid python3 ${(q)${commands[python3]:A:t}} && print -r -- cleaned > ${(q)wd}/cleaned } &!" \
    "python3 ${(q)wd}/editor.py ${(q)wd}/editor.pid" > "$wd/session.zsh"
  script -qfc "zsh -f ${(q)wd}/session.zsh" /dev/null </dev/null >/dev/null 2>&1 &
  terminal=$!
  for attempt in {1..100}; do [[ -s "$wd/editor.pid" ]] && break; sleep 0.05; done
  editor_pid="$(<"$wd/editor.pid")"
  sleep 0.2
  check 'the watchdog leaves a live session alone' alive "$(kill -0 "$editor_pid" 2>/dev/null && print alive || print gone)"
  kill -KILL "$terminal"   # closing the terminal hangs up the session
  for attempt in {1..100}; do [[ -s "$wd/cleaned" ]] && ! kill -0 "$editor_pid" 2>/dev/null && break; sleep 0.05; done
  check 'a hangup stops an editor that ignores SIGHUP' gone "$(kill -0 "$editor_pid" 2>/dev/null && print alive || print gone)"
  check 'a hangup runs the session cleanup' cleaned "$(cat "$wd/cleaned" 2>/dev/null)"
  kill -KILL "$editor_pid" 2>/dev/null
  exit "$fail"
) || fail=1
else
  print -r -- '    - skipped (needs script and python3)'
fi

print -r -- '  [error page folding]'
check 'folds long log lines' $'abcd\nefgh\nij\nkl' "$(print -rl -- abcdefghij kl | _hxp_fold 4)"

print -r -- '  [unclaimed Ghostty split]'
(
  export WINDOWID=42 GHOSTTY_SURFACE_ID=editor
  zmodload zsh/system
  term_pid=$sysparams[pid]
  before="$(pgrep -P "$term_pid" | tr '\n' ' ')"
  env WINDOWID=7 GHOSTTY_SURFACE_ID=elsewhere sleep 10 & other_window=$!
  env WINDOWID=42 GHOSTTY_SURFACE_ID=editor sleep 10 & same_surface=$!
  env WINDOWID=42 GHOSTTY_SURFACE_ID=split sleep 10 & split=$!
  preview_shell=''
  for attempt in {1..100}; do
    preview_shell="$(_hxp_new_split_shell "$term_pid" "$before")" && break
    sleep 0.02
  done
  check 'finds only the new split in this window' "$split" "${preview_shell%%:*}"
  preview_dir="$work/unclaimed-preview" preview_pane=''
  mkdir -p "$preview_dir"
  _hxp_release_split
  wait "$split"
  check 'hangs up a split that never started fancy-cat' 129 "$?"
  check 'removes the preview directory' no "$([[ -e "$work/unclaimed-preview" ]] && print yes || print no)"
  preview_dir="$work/reused-preview" preview_shell="$other_window:0"
  mkdir -p "$preview_dir"
  _hxp_release_split
  check 'never signals a reused PID' alive "$(kill -0 "$other_window" 2>/dev/null && print alive || print gone)"
  kill "$other_window" "$same_surface" 2>/dev/null
  exit "$fail"
) || fail=1

print -r -- '  [inverse search from fancy-cat]'
(
  export XDG_RUNTIME_DIR="$work/jump-runtime" HXP_TEST_SPAWNED="$work/spawned-editor"
  mkdir -p "$work/jump-bin"
  cat > "$work/jump-bin/hx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$HXP_TEST_SPAWNED"
EOF
  chmod +x "$work/jump-bin/hx"
  export PATH="$work/jump-bin:$PATH"
  sf="$(_hxp_state_file "${project:A}/main.tex")"
  mkdir -p "${sf:h}"
  for viewer in fancy-cat zathura; do
    print -rl -- "src=$project/main.tex" "pdf=$project/main.pdf" "viewer=$viewer" editor=helix "pid=$$" > "$sf"
    rm -f -- "$HXP_TEST_SPAWNED"
    bash "$repo/bin/hxp-jump" "$project/main.tex:3" 2>/dev/null
    rc=$?
    if [[ "$viewer" == fancy-cat ]]; then
      check 'unreachable editor reports failure inside fancy-cat' 1 "$rc"
      check 'fancy-cat never gets a second editor' no "$([[ -e "$HXP_TEST_SPAWNED" ]] && print yes || print no)"
    else
      check 'GUI viewers never start an editor without a terminal' 1 "$rc"
      check 'no terminal, no spawned editor' no "$([[ -e "$HXP_TEST_SPAWNED" ]] && print yes || print no)"
      if (( $+commands[script] )); then
        script -qec "bash ${(q)repo}/bin/hxp-jump ${(q)project}/main.tex:3" /dev/null >/dev/null 2>&1 </dev/null
        check 'a terminal still gets a new editor' "${project:A}/main.tex:3" "$(cat "$HXP_TEST_SPAWNED" 2>/dev/null)"
      fi
    fi
  done
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
printf 'Chapter text. First page.\fChapter text. Distinct context.\f'
EOF
  ln -s "$repo/bin/hxp-typtext" "$work/bin/hxp-typtext"
  print -rl -- 'Chapter text.' 'Distinct context.' > "$project/chapters/intro.typ"
  chmod +x "$work/bin/wmctrl" "$work/bin/zathura" "$work/bin/gdbus" "$work/bin/pdftotext"
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
  check 'neighboring text selects the second occurrence in the owned Zathura' 'org.pwmt.zathura.PID-222 1' "$(cat "$HXP_TEST_PAGE_TARGET" 2>/dev/null)"
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
