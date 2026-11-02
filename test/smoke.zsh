#!/usr/bin/env zsh
# Compile success, failure, and watch recovery; skip missing toolchains.

emulate -L zsh
set -u

repo="${0:A:h:h}"
source "$repo/zsh/hxp-lib.zsh"
export PATH="$repo/bin:$PATH"          # make hxp-mdline resolvable

typeset -g fail=0
typeset -ga skips
check() {  # desc expected actual
  if [[ "$2" == "$3" ]]; then
    print -r -- "    ✓ $1"
  else
    print -r -- "    ✗ $1: expected [$2] got [$3]"
    fail=1
  fi
}
is_pdf() { [[ -s "$1" ]] && head -c5 -- "$1" 2>/dev/null | grep -q '%PDF' }

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

compile() {  # src ext
  local src="$1" ext="$2" dir="${1:h}" stem="${${1:t}:r}"
  _hxp_compile_once "$src" "$ext" "$dir" "$stem" \
    "$(_hxp_pdf_for "$src" "$ext")" "$dir/.${stem}.tmp.pdf" "$dir/.${stem}.error.log" \
    "$dir/.${stem}.error.md" "$dir/.${stem}.debug.tex" "$dir/.hxp_build_${stem}"
}

if _hxp_need_cmd pandoc; then
  print -r -- "  [markdown]"
  d="$work/md"; mkdir -p "$d"
  print -rl -- '# Hello' '' 'Inline \(x\).' '' '\[' '\operatorname{CAS}(n_e,n_o)' '\]' >| "$d/a.md"
  compile "$d/a.md" md; rc=$?
  check "md good rc"  0 "$rc"
  check "md good pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  print -rl -- '# Bad' '' 'text \undefinedcontrolsequence more' >| "$d/a.md"
  compile "$d/a.md" md; rc=$?
  check "md bad rc"        1 "$rc"
  check "md bad error pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"
else
  skips+=(markdown)
fi

if _hxp_need_cmd latexmk; then
  print -r -- "  [latex]"
  d="$work/tex"; mkdir -p "$d"
  print -rl -- '\documentclass{article}' '\begin{document}' 'Hi.' '\end{document}' >| "$d/a.tex"
  compile "$d/a.tex" tex; rc=$?
  check "tex good rc"  0 "$rc"
  check "tex good pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  print -rl -- '\documentclass{article}' '\begin{document}' '\undefinedcontrolsequence' '\end{document}' >| "$d/a.tex"
  compile "$d/a.tex" tex; rc=$?
  check "tex bad rc"        1 "$rc"
  check "tex bad error pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  # Included sources must build from the project root.
  d="$work/tex project"; mkdir -p "$d/chapters"
  print -rl -- '\documentclass{article}' '\begin{document}' '\input{chapters/intro}' '\end{document}' >| "$d/main.tex"
  print -r -- 'Included chapter.' >| "$d/chapters/intro.tex"
  (cd "$work"; compile "$d/chapters/intro.tex" tex); rc=$?
  check "tex included source from outside project" 0 "$rc"
  check "tex included source root pdf" 1 "$(is_pdf "$d/main.pdf" && echo 1 || echo 0)"
  check "tex no stray chapter pdf" 0 "$([[ -e "$d/chapters/intro.pdf" ]] && echo 1 || echo 0)"
else
  skips+=(latex)
fi

if _hxp_need_cmd typst; then
  print -r -- "  [typst]"
  d="$work/typ"; mkdir -p "$d"
  print -rl -- '= Hello' '' 'World.' >| "$d/a.typ"
  compile "$d/a.typ" typ; rc=$?
  check "typ good rc"  0 "$rc"
  check "typ good pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  # Publishing must preserve readers of the previous PDF.
  old_digest="$(sha256sum < "$d/a.pdf")"
  exec {reader_fd}< "$d/a.pdf"
  print -rl -- '= Updated' '' 'New content after saving.' >| "$d/a.typ"
  compile "$d/a.typ" typ; rc=$?
  check 'typ updated rc' 0 "$rc"
  check 'typ keeps an open reader stable' "$old_digest" "$(sha256sum <&$reader_fd)"
  exec {reader_fd}<&-

  print -rl -- '= Bad' '#let x =' >| "$d/a.typ"
  compile "$d/a.typ" typ; rc=$?
  check "typ bad rc"        1 "$rc"
  check "typ bad error pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  d="$work/typ project"; mkdir -p "$d/chapters"
  print -rl -- '= Root' '#include "chapters/intro.typ"' >| "$d/main.typ"
  print -r -- 'Included chapter.' >| "$d/chapters/intro.typ"
  compile "$d/chapters/intro.typ" typ; rc=$?
  check "typ included source rc" 0 "$rc"
  check "typ included source root pdf" 1 "$(is_pdf "$d/main.pdf" && echo 1 || echo 0)"
  check "typ no stray chapter pdf" 0 "$([[ -e "$d/chapters/intro.pdf" ]] && echo 1 || echo 0)"

  print -r -- "  [typst watch loop]"
  d2="$work/typw"; mkdir -p "$d2"
  src="$d2/t.typ"; pdf="$d2/t.pdf"
  errlog="$d2/.t.error.log"; errmd="$d2/.t.error.md"
  tmp="$d2/.t.tmp.pdf"; dtex="$d2/.t.debug.tex"
  print -rl -- '= Doc' '#let x =' >| "$src"

  print -rl -- \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:23] compiling ...' '' \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:23] compiled with errors' '' \
    'error: expected expression' '  ┌─ t.typ:2:8' '  │' '2 │ #let x =' '  │         ^' \
    | _hxp_typst_watch_render "$src" typ "$errlog" "$errmd" "$tmp" "$dtex" "$pdf"
  check "watch fail -> err_md"     1 "$([[ -f "$errmd" ]] && echo 1 || echo 0)"
  check "watch fail -> error pdf"  1 "$(is_pdf "$pdf" && echo 1 || echo 0)"
  check "watch fail -> err_log"    1 "$(grep -q 'expected expression' "$errlog" && echo 1 || echo 0)"

  # Retain watch output to recover from errors without re-exporting.
  watch_pdf="${tmp:r}.watch.pdf"
  print -rl -- '= Watch snapshot' 'Completed output.' >| "$d2/good.typ"
  typst compile "$d2/good.typ" "$watch_pdf"
  old_digest="$(sha256sum < "$pdf")"
  exec {reader_fd}< "$pdf"
  print -rl -- \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:25] compiling ...' '' \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:25] compiled successfully in 2.04 ms' \
    | _hxp_typst_watch_render "$src" typ "$errlog" "$errmd" "$tmp" "$dtex" "$pdf" "$watch_pdf"
  check "watch ok -> no err_md"    0 "$([[ -f "$errmd" ]] && echo 1 || echo 0)"
  check 'watch publishes the completed PDF' "$(sha256sum < "$watch_pdf")" "$(sha256sum < "$pdf")"
  check 'watch keeps an open reader stable' "$old_digest" "$(sha256sum <&$reader_fd)"
  exec {reader_fd}<&-
  check 'watch retains its private output' 1 "$(is_pdf "$watch_pdf" && echo 1 || echo 0)"
  _hxp_sweep_artifacts "$tmp" "$errlog" "$errmd" "$dtex" '' "$d2/.hxp_build_t"
  check 'watch output is swept on exit' 0 "$([[ -e "$watch_pdf" ]] && echo 1 || echo 0)"

  if _hxp_need_cmd inotifywait && _hxp_need_cmd pandoc; then
    print -r -- '  [native typst watch publication]'
    (
      source "$repo/zsh/hxp-main.zsh"
      source "$repo/zsh/hxp-lib.zsh"
      export HXP_NO_NATIVE_TYP=0
      live_dir="$work/live-watch"
      mkdir -p "$live_dir"
      live_src="$live_dir/live.typ"
      live_pdf="$live_dir/live.pdf"
      live_stage="$live_dir/.live.tmp.watch.pdf"
      live_error="$live_dir/.live.error.md"
      print -rl -- '= Original' 'Stable reader.' > "$live_src"
      wpdf -q --no-initial "$live_src" > "$live_dir/watcher.log" 2>&1 &
      native_pid=$!
      trap 'pkill -TERM -P "$native_pid" 2>/dev/null; kill -TERM "$native_pid" 2>/dev/null; wait "$native_pid" 2>/dev/null' EXIT
      for attempt in {1..200}; do
        [[ -s "$live_pdf" ]] && break
        sleep 0.05
      done
      check 'native watch publishes its first PDF' 1 "$(is_pdf "$live_pdf" && echo 1 || echo 0)"
      if [[ -s "$live_pdf" ]]; then
        old_digest="$(sha256sum < "$live_pdf")"
        exec {reader_fd}< "$live_pdf"
        print -rl -- '= Updated' 'Next stable snapshot.' > "$live_src"
        for attempt in {1..200}; do
          [[ "$(sha256sum < "$live_pdf")" != "$old_digest" ]] && break
          sleep 0.05
        done
        check 'native watch updates after a save' yes "$([[ "$(sha256sum < "$live_pdf")" != "$old_digest" ]] && print yes)"
        check 'native watch preserves an external reader' "$old_digest" "$(sha256sum <&$reader_fd)"
        exec {reader_fd}<&-

        print -rl -- '= Broken' '#let x =' > "$live_src"
        for attempt in {1..200}; do
          [[ -s "$live_error" ]] && break
          sleep 0.05
        done
        check 'native watch reports an error' yes "$([[ -s "$live_error" ]] && print yes)"
        print -rl -- '= Updated' 'Next stable snapshot.' > "$live_src"
        for attempt in {1..200}; do
          [[ ! -e "$live_error" ]] && break
          sleep 0.05
        done
        check 'native watch recovers unchanged good content' no "$([[ -e "$live_error" ]] && print yes || print no)"
        check 'native watch restores its good PDF' "$(sha256sum < "$live_stage")" "$(sha256sum < "$live_pdf")"
      fi
      exit "$fail"
    ) || fail=1
  fi
else
  skips+=(typst)
fi

print -r -- ""
(( ${#skips} )) && print -r -- "  skipped (missing tools): ${skips[*]}"
if (( fail == 0 )); then
  print -r -- "SMOKE TESTS PASSED"
  exit 0
else
  print -r -- "SMOKE TESTS FAILED"
  exit 1
fi
