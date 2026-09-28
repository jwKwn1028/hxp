#!/usr/bin/env zsh
# Smoke test for the compile pipeline. For each language whose toolchain is
# present it asserts: a good source produces a real PDF (rc 0), and a broken
# source fails (rc 1) but still produces an error PDF. Languages whose tools
# are missing are SKIPPED, so this is useful locally with a partial toolchain
# and exhaustive in CI where everything is installed.
#
# Also exercises the typst `watch` render loop (#1) against a canned transcript
# so the error-surfacing path is covered without a long-running watcher.

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

# ---------- markdown ----------
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

# ---------- latex ----------
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

  # Launch on an included source from outside the project. latexmk must run
  # at the root so relative inputs resolve; the output still belongs there.
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

# ---------- typst (compile + the watch render loop) ----------
if _hxp_need_cmd typst; then
  print -r -- "  [typst]"
  d="$work/typ"; mkdir -p "$d"
  print -rl -- '= Hello' '' 'World.' >| "$d/a.typ"
  compile "$d/a.typ" typ; rc=$?
  check "typ good rc"  0 "$rc"
  check "typ good pdf" 1 "$(is_pdf "$d/a.pdf" && echo 1 || echo 0)"

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

  # ----- typst `watch` render loop, fed a canned 0.15 transcript -----
  print -r -- "  [typst watch loop]"
  d2="$work/typw"; mkdir -p "$d2"
  src="$d2/t.typ"; pdf="$d2/t.pdf"
  errlog="$d2/.t.error.log"; errmd="$d2/.t.error.md"
  tmp="$d2/.t.tmp.pdf"; dtex="$d2/.t.debug.tex"
  print -rl -- '= Doc' '#let x =' >| "$src"

  # failure transcript -> err_md written, error PDF rendered
  print -rl -- \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:23] compiling ...' '' \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:23] compiled with errors' '' \
    'error: expected expression' '  ┌─ t.typ:2:8' '  │' '2 │ #let x =' '  │         ^' \
    | _hxp_typst_watch_render "$src" typ "$errlog" "$errmd" "$tmp" "$dtex" "$pdf"
  check "watch fail -> err_md"     1 "$([[ -f "$errmd" ]] && echo 1 || echo 0)"
  check "watch fail -> error pdf"  1 "$(is_pdf "$pdf" && echo 1 || echo 0)"
  check "watch fail -> err_log"    1 "$(grep -q 'expected expression' "$errlog" && echo 1 || echo 0)"

  # success transcript -> err_md cleared
  print -rl -- \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:25] compiling ...' '' \
    'watching t.typ' 'writing to t.pdf' '' '[14:08:25] compiled successfully in 2.04 ms' \
    | _hxp_typst_watch_render "$src" typ "$errlog" "$errmd" "$tmp" "$dtex" "$pdf"
  check "watch ok -> no err_md"    0 "$([[ -f "$errmd" ]] && echo 1 || echo 0)"
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
