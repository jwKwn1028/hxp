#!/usr/bin/env zsh
# Toolchain-free tests for the compiler-log parsers in hxp-lib.zsh.
#
# These run the awk-based extractors under *every* awk on the system (gawk,
# mawk, and whatever /usr/bin/awk is) via the $HXP_AWK override, guarding the
# POSIX-awk rewrite of _hxp_error_location against gawk-only regressions.
# No compilers needed, so this is the fast CI gate.

emulate -L zsh
set -u

repo="${0:A:h:h}"
source "$repo/zsh/hxp-lib.zsh"

typeset -g fail=0
check() {  # desc expected actual
  if [[ "$2" == "$3" ]]; then
    print -r -- "    ✓ $1"
  else
    print -r -- "    ✗ $1: expected [$2] got [$3]"
    fail=1
  fi
}

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# ---- fixtures ----------------------------------------------------------
latex_log="$work/latex.log"
cat >| "$latex_log" <<'EOF'
This is XeTeX, Version 3.14159265
(./main.tex
./main.tex:42: Undefined control sequence.
l.42 \badmacro
              text after
EOF

typst_log="$work/typst.log"      # typst 0.15 diagnostic shape
cat >| "$typst_log" <<'EOF'
error: unknown variable: foo
  ┌─ report.typ:7:3
  │
7 │ #foo
  │  ^^^
EOF

multi_typst_log="$work/multi.typ.log"
cat >| "$multi_typst_log" <<'EOF'
error: unknown variable: a
  ┌─ m.typ:2:1
error: unexpected end of block
  ┌─ m.typ:5:0
EOF

# ---- which awks to exercise -------------------------------------------
typeset -a awks
local a
for a in gawk mawk awk; do
  command -v "$a" >/dev/null 2>&1 && awks+=("$a")
done
# de-dup (awk may be a symlink to gawk/mawk; harmless to run twice)
print -r -- "awks under test: ${awks[*]}"

local loc f l c
for a in $awks; do
  print -r -- "  [awk=$a]"

  # latex file-line-error -> file + line, no col
  loc="$(HXP_AWK=$a _hxp_error_location "$latex_log" "$work/main.tex")"
  IFS=$'\t' read -r f l c <<< "$loc"
  check "latex line"        42        "$l"
  check "latex col empty"   ""        "$c"
  check "latex file"        main.tex  "${f:t}"

  # typst location line "┌─ report.typ:7:3" -> file + line + col
  loc="$(HXP_AWK=$a _hxp_error_location "$typst_log" "$work/report.typ")"
  IFS=$'\t' read -r f l c <<< "$loc"
  check "typst line"        7          "$l"
  check "typst col"         3          "$c"
  check "typst file"        report.typ "${f:t}"

  # counts & primary
  check "typst count"       1 "$(HXP_AWK=$a _hxp_error_count "$typst_log")"
  check "multi typst count" 2 "$(HXP_AWK=$a _hxp_error_count "$multi_typst_log")"
  check "latex count"       1 "$(HXP_AWK=$a _hxp_error_count "$latex_log")"
  check "typst primary"     "error: unknown variable: foo" \
        "$(HXP_AWK=$a _hxp_primary_error "$typst_log")"
done

if (( fail == 0 )); then
  print -r -- "PARSE TESTS PASSED"
  exit 0
else
  print -r -- "PARSE TESTS FAILED"
  exit 1
fi
