#!/usr/bin/env zsh
# Build and watch regressions; skip unavailable toolchains.

emulate -L zsh
set -u

repo="${0:A:h:h}"
source "$repo/zsh/hxp-lib.zsh"
export PATH="$repo/bin:$PATH"

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
export XDG_RUNTIME_DIR="$work/runtime"

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
  check 'md error report keeps TeX backslashes' yes \
    "$(grep -qF -- '\undefinedcontrolsequence' "$d/.a.error.md" && print yes || print no)"
  if _hxp_need_cmd typst; then
    check 'md error page is rendered by Typst' yes "$(grep -aq 'Typst' "$d/a.pdf" && print yes || print no)"
  fi

  if _hxp_need_cmd xelatex && _hxp_need_cmd pdftotext && cjk_font="$(_hxp_cjk_font)"; then
    (
      # Only the nested bibliography contains CJK.
      d="$work/md-cjk-bibliography"
      mkdir -p "$d/references with spaces"
      print -rl -- '@book{korean,' '  author = {Kim, Jisu},' '  title = {한국어 제목},' '  year = {2021}' '}' > "$d/references with spaces/refs.bib"
      print -rl -- '---' 'bibliography: "references with spaces/refs.bib"' '---' \
        'An English document citing a book [@korean].' > "$d/notes.md"
      unset HXP_CJK_FONT
      export HXP_CJK_FONT_RESOLVED="$cjk_font"
      compile "$d/notes.md" md; rc=$?
      check 'configured CJK bibliography compiles' 0 "$rc"
      check 'configured bibliography keeps Korean glyphs in the PDF' yes \
        "$(pdftotext -q "$d/notes.pdf" - | grep -qF '한국어 제목' && print yes || print no)"
      if _hxp_need_cmd latexmk; then
        _hxp_need_cmd() { [[ "$1" != latexmk ]] && command -v "$1" >/dev/null 2>&1 }
        compile "$d/notes.md" md; rc=$?
        check 'Pandoc-direct CJK bibliography compiles' 0 "$rc"
        check 'Pandoc-direct bibliography keeps Korean glyphs' yes \
          "$(pdftotext -q "$d/notes.pdf" - | grep -qF '한국어 제목' && print yes || print no)"
      fi
      exit "$fail"
    ) || fail=1
  else
    skips+=(CJK-bibliography)
  fi

  if _hxp_need_cmd latexmk; then
    # Exercise paths exceeding TeX's 79-column log default.
    d="$work/md/deep-$(printf '%080d' 0)"; mkdir -p "$d"
    print -rl -- '# Bad' '' 'text \undefinedcontrolsequence more' >| "$d/a.md"
    compile "$d/a.md" md
    first="$("$repo/bin/hxp-first-error" "$d/a.md" 2>&1)"
    check 'md first error stays in the Markdown source' "$d/a.md" "${first%%:*}"
  fi
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
  sidecar_inode="$(stat -c %i -- "$d/a.synctex.gz" 2>/dev/null)"
  compile "$d/a.tex" tex
  check 'tex SyncTeX sidecar is replaced, not overwritten' yes \
    "$([[ -s "$d/a.synctex.gz" && "$(stat -c %i -- "$d/a.synctex.gz")" != "$sidecar_inode" ]] && print yes || print no)"
  check 'tex rebuild runs one LaTeX pass' 1 "$(grep -c '^Latexmk: applying rule' "$d/.a.error.log" 2>/dev/null)"

  print -rl -- '\documentclass{article}' '\begin{document}' '\undefinedcontrolsequence' '\end{document}' >| "$d/a.tex"
  compile "$d/a.tex" tex; rc=$?
  check "tex bad rc"        1 "$rc"
  check "tex bad error pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"
  if _hxp_need_cmd typst; then
    check 'tex error page is rendered by Typst' yes "$(grep -aq 'Typst' "$d/a.pdf" && print yes || print no)"
    if _hxp_need_cmd pdftotext; then
      check 'tex error page names the error' yes \
        "$(pdftotext -q "$d/a.pdf" - | grep -q 'Undefined control sequence' && print yes || print no)"
      (
        # Both reports must share zsh's $$.
        d="$work/concurrent-error-pdfs"
        mkdir -p "$d"
        for name in alpha beta; do
          print -r -- "Source for $name" > "$d/$name.tex"
          print -r -- "$d/$name.tex:1: Diagnostic for $name." > "$d/$name.log"
        done
        _hxp_make_error_pdf "$d/alpha.tex" tex "$d/alpha.log" "$d/alpha.md" "$d/alpha.pdf" '' "$d/alpha.final.pdf" &
        a_pid=$!
        _hxp_make_error_pdf "$d/beta.tex" tex "$d/beta.log" "$d/beta.md" "$d/beta.pdf" '' "$d/beta.final.pdf" &
        b_pid=$!
        wait "$a_pid"; check 'first concurrent error PDF renders' 0 "$?"
        wait "$b_pid"; check 'second concurrent error PDF renders' 0 "$?"
        for name in alpha beta; do
          text="$(pdftotext -q "$d/$name.pdf" -)"
          other=alpha; [[ "$name" == alpha ]] && other=beta
          check "$name PDF retains its own diagnostic and location" yes \
            "$([[ "$text" == *"Diagnostic for $name."* && "$text" == *"$name.tex:1"* && \
                  "$text" != *"Diagnostic for $other."* ]] && print yes || print no)"
        done
        exit "$fail"
      ) || fail=1
    fi
  fi

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

  old_digest="$(sha256sum < "$d/a.pdf")"
  exec {reader_fd}< "$d/a.pdf"
  print -rl -- '= Updated' '' 'New content after saving.' >| "$d/a.typ"
  compile "$d/a.typ" typ; rc=$?
  check 'typ updated rc' 0 "$rc"
  check 'typ keeps an open reader stable' "$old_digest" "$(sha256sum <&$reader_fd)"
  exec {reader_fd}<&-

  good="$(sha256sum < "$d/a.pdf")"
  print -rl -- '= Bad' '#let x =' >| "$d/a.typ"
  HXP_KEEP_LAST_GOOD=1 compile "$d/a.typ" typ
  check 'last-good reports a failed compile' 1 "$?"
  check 'last-good preserves the PDF' "$good" "$(sha256sum < "$d/a.pdf")"
  check 'editor command resolves the first error' "$d/a.typ:2:8" "$(HXP_SESSION_SRC="$d/a.typ" "$repo/bin/hxp-first-error")"
  compile "$d/a.typ" typ; rc=$?
  check "typ bad rc"        1 "$rc"
  check "typ bad error pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

  # Refresh errors until the first successful build.
  d="$work/typ first failure"; mkdir -p "$d"
  print -rl -- '= Bad' '#let x =' >| "$d/a.typ"
  HXP_KEEP_LAST_GOOD=1 compile "$d/a.typ" typ
  check 'last-good without a PDF renders an error page' 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"
  first_error="$(sha256sum < "$d/a.pdf")"
  print -rl -- '= Bad' '' '' '#let y =' >| "$d/a.typ"
  HXP_KEEP_LAST_GOOD=1 compile "$d/a.typ" typ
  check 'last-good refreshes an earlier error page' yes "$([[ "$(sha256sum < "$d/a.pdf")" != "$first_error" ]] && print yes)"
  print -rl -- '= Fixed' 'Good.' >| "$d/a.typ"
  compile "$d/a.typ" typ
  good="$(sha256sum < "$d/a.pdf")"
  print -rl -- '= Bad' '#let z =' >| "$d/a.typ"
  HXP_KEEP_LAST_GOOD=1 compile "$d/a.typ" typ
  check 'last-good keeps the first good build' "$good" "$(sha256sum < "$d/a.pdf")"

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

  # Render errors while the watch pipe stays open.
  zmodload zsh/datetime
  rm -f -- "$pdf"
  started=$EPOCHREALTIME
  {
    print -rl -- \
      'watching t.typ' 'writing to t.pdf' '' '[14:08:24] compiled with errors' '' \
      'error: expected expression' '  ┌─ t.typ:2:8' '  │' '2 │ #let x =' '  │         ^'
    sleep 1
  } | _hxp_typst_watch_render "$src" typ "$errlog" "$errmd" "$tmp" "$dtex" "$pdf" &
  while (( EPOCHREALTIME - started < 1 )) && ! is_pdf "$pdf"; do sleep 0.01; done
  rendered=$(( EPOCHREALTIME - started ))
  wait
  check 'watch fail renders while typst keeps running' yes \
    "$(is_pdf "$pdf" && (( rendered < 0.5 )) && print yes || printf 'no (%.2f s)' "$rendered")"

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
      export HXP_NO_NATIVE_TYP=0 HXP_KEEP_LAST_GOOD=1
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

        good="$(sha256sum < "$live_pdf")"
        print -rl -- '= Broken' '#let x =' > "$live_src"
        for attempt in {1..200}; do
          [[ -s "$live_error" ]] && break
          sleep 0.05
        done
        check 'native last-good preserves the PDF' "$good" "$(sha256sum < "$live_pdf")"
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
