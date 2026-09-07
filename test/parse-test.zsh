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

# ---- watch scope: _hxp_watch_exts / _hxp_watch_match ------------------
# Pure, awk-free — pins the extension sets and, crucially, the exclusions that
# stop hxp's own artifacts (the .md error doc, the md->tex intermediate) from
# self-triggering a recompile loop under the inotifywait fallback.
print -r -- "  [watch scope]"
check "md exts"   "md,bib"           "$(_hxp_watch_exts md)"
check "tex exts"  "tex,bib,sty,cls"  "$(_hxp_watch_exts tex)"
check "typ exts"  "typ,bib,yml,yaml" "$(_hxp_watch_exts typ)"

wm() { _hxp_watch_match "$1" "$2" && print 1 || print 0 }
# fires: opened file, nested include, sibling bib
check "tex src"       1 "$(wm tex /p/main.tex)"
check "tex nested"    1 "$(wm tex /p/chapters/intro.tex)"
check "tex sibling bib" 1 "$(wm tex /p/refs.bib)"
check "md src"        1 "$(wm md /p/notes.md)"
check "md sibling bib" 1 "$(wm md /p/refs.bib)"
check "typ include"   1 "$(wm typ /p/sections/a.typ)"
# quiet: wrong ext, our dot-artifacts, build-dir churn, rendered output
check "tex wrong ext" 0 "$(wm tex /p/notes.md)"
check "md err doc"    0 "$(wm md /p/.notes.error.md)"
check "md debug tex"  0 "$(wm md /p/.notes.debug.tex)"
check "build-dir tex" 0 "$(wm md /p/.hxp_build_notes/notes.hxp.tex)"
check "output pdf"    0 "$(wm tex /p/main.pdf)"
check "typ errdoc"    0 "$(wm typ /p/.t.tmp.errdoc.typ)"

# ---- md -> tex line mapping: hxp-texline -------------------------------
# synctex names only pandoc's intermediate, so a md cursor line must be
# re-expressed as a tex line before the viewer can move. Fixture is hand-written
# (no pandoc needed): the heuristic only leans on prose surviving into the tex.
print -r -- "  [md -> tex line map]"

tl_md="$work/doc.md"
tl_tex="$work/doc.hxp.tex"
cat >| "$tl_md" <<'EOF'
# Overview

The compiler writes its output beside the source.

## Configuration

Set the margin with an environment variable.

- Markdown
- LaTeX
EOF

cat >| "$tl_tex" <<'EOF'
\documentclass{article}
% Configuration of the preamble mentions Markdown early on.
\begin{document}
\hypertarget{overview}{%
\section{Overview}\label{overview}}

The compiler writes its output beside the source.

\hypertarget{configuration}{%
\subsection{Configuration}\label{configuration}}

Set the margin with an environment variable.

\begin{itemize}
\tightlist
\item
  Markdown
\item
  LaTeX
\end{itemize}
\end{document}
EOF

tl() { "$repo/bin/hxp-texline" "$tl_md" "$tl_tex" "$1" }

check "heading maps to \section"   5  "$(tl 1)"
check "prose maps verbatim"         7  "$(tl 3)"
check "subheading maps"            10  "$(tl 5)"
check "second prose block"         12  "$(tl 7)"
# A bare list item is a weak anchor: "Markdown" also appears in the preamble
# (excluded by the \begin{document} floor) and could match anywhere. The
# preceding-line floor keeps it in the itemize.
check "weak list anchor"           17  "$(tl 9)"
# Blank lines have no anchor of their own and fall through to a neighbour.
check "blank line falls outward"    7  "$(tl 2)"
# Out-of-range and junk input map to nothing rather than to line 1.
check "line past EOF"              ""  "$(tl 9999)"
check "missing tex file"           ""  "$("$repo/bin/hxp-texline" "$tl_md" "$work/nope.tex" 3)"

# A contents list repeats every heading, so heading text appears twice: once in
# the list, once as the section. Each cursor position must reach its own copy —
# and a contents entry must never drag the search floor past the list.
tl2_md="$work/toc.md"
tl2_tex="$work/toc.hxp.tex"
cat >| "$tl2_md" <<'EOF'
# Manual

Introductory prose that is long enough to anchor the search reliably.

## Contents

- [Viewer keybindings](#viewer-keybindings)
- [Forward search (editor to PDF)](#forward-search)

## Viewer keybindings

Keys the viewer binds by default and how to change them.
EOF

cat >| "$tl2_tex" <<'EOF'
\documentclass{article}
\begin{document}
\section{Manual}\label{manual}

Introductory prose that is long enough to anchor the search
reliably.

\subsection{Contents}\label{contents}

\begin{itemize}
\item
  \protect\hyperlink{viewer-keybindings}{Viewer keybindings}
\item
  \protect\hyperlink{forward-search}{Forward search (editor to PDF)}
\end{itemize}

\subsection{Viewer keybindings}\label{viewer-keybindings}

Keys the viewer binds by default and how to change them.
\end{document}
EOF

tl2() { "$repo/bin/hxp-texline" "$tl2_md" "$tl2_tex" "$1" }

check "contents entry -> list"  12 "$(tl2 7)"
check "heading -> section"      17 "$(tl2 10)"
check "prose after heading"     19 "$(tl2 12)"

# ---- typst search phrases: hxp-typtext -------------------------------
# No synctex for typst, so forward search looks for the line's text in the page.
# The emitted phrase must be text that really reaches the page: code lines yield
# nothing, and cut-out constructs (math, calls) split the line rather than
# joining prose that was never adjacent.
print -r -- "  [typst search phrases]"

tt_typ="$work/doc.typ"
cat >| "$tt_typ" <<'EOF'
#set page(width: 12cm)
#let author = "Someone"

= Introduction to Embeddings

This paragraph explains the embedding approach in detail.

// a comment that must never be searched for
We compute $E = m c^2$ and then refine the geometry iteratively.
#figure(caption: [Convergence of the total energy])[table]
EOF

tt()  { "$repo/bin/hxp-typtext" "$tt_typ" "$1" | head -1 }
tt1() { "$repo/bin/hxp-typtext" "$tt_typ" "$1" }

# Heading markers and code sigils are stripped, prose survives whole.
check "heading drops ="        "Introduction to Embeddings" "$(tt 4)"
check "prose kept whole"       "This paragraph explains the embedding approach in detail." "$(tt 6)"
# Math is a separator: the joined form ("We compute and then...") is on no page.
check "math splits runs"       "and then refine the geometry iteratively." "$(tt 9)"
check "no joined-over-math"    "0" "$(tt1 9 | grep -c 'We compute and then')"
# Content inside a function call still renders, so it is worth searching for.
check "figure caption kept"    "Convergence of the total energy" "$(tt 10)"
# A comment has no page text — must fall through to a neighbour.
check "comment not searched"   "0" "$(tt1 8 | grep -c 'never be searched')"
# Pure code lines emit nothing of their own.
check "code line skipped"      "0" "$(tt1 2 | grep -c 'Someone')"
check "line past EOF"          "" "$(tt 9999)"

# ---- editor dispatch: helix vs micro -----------------------------------
# The two editors take a cursor position in incompatible shapes (helix glues it
# onto the path, micro takes a separate +line:col), so the argv builder is what
# `hxp --micro` actually rides on. Pure string work — no editor is spawned.
print -r -- "  [editor dispatch]"

check "editor default"    helix "$(unset HXP_EDITOR; _hxp_editor)"
check "editor micro"      micro "$(HXP_EDITOR=micro; _hxp_editor)"
check "editor case-fold"  micro "$(HXP_EDITOR=MICRO; _hxp_editor)"
check "editor helix"      helix "$(HXP_EDITOR=helix; _hxp_editor)"
# An unknown name has no argv shape here, so it must not be spawned blindly.
check "editor unknown"    helix "$(HXP_EDITOR=vim; _hxp_editor)"
check "bin helix"         hx    "$(_hxp_editor_bin helix)"
check "bin micro"         micro "$(_hxp_editor_bin micro)"

# Named eargv, not argv: `argv` is the positional-parameter array in zsh, and
# a local of that name inside a wrapper silently empties "$@".
eargv() {
  local -a a; a=( "${(@f)$(_hxp_editor_argv "$@")}" )
  print -r -- "${(j:|:)a}"
}

check "helix bare"      "hx|/p/a.tex"                    "$(eargv helix /p/a.tex '' '')"
check "helix line"      "hx|/p/a.tex:42"                 "$(eargv helix /p/a.tex 42 '')"
check "helix line+col"  "hx|/p/a.tex:42:7"               "$(eargv helix /p/a.tex 42 7)"
check "helix extras"    "hx|/p/a.tex|/p/e.log|/p/d.tex"  "$(eargv helix /p/a.tex '' '' /p/e.log /p/d.tex)"
check "micro bare"      "micro|/p/a.tex"                 "$(eargv micro /p/a.tex '' '')"
check "micro line"      "micro|+42|/p/a.tex"             "$(eargv micro /p/a.tex 42 '')"
check "micro line+col"  "micro|+42:7|/p/a.tex"           "$(eargv micro /p/a.tex 42 7)"
check "micro extras"    "micro|+42:7|/p/a.tex|/p/e.log"  "$(eargv micro /p/a.tex 42 7 /p/e.log)"
# Paths with spaces stay single words — the launcher runs the array, not a string.
check "space in path"   "micro|+3|/p/my doc.md"          "$(eargv micro '/p/my doc.md' 3 '')"

# ---- error jump target -------------------------------------------------
# _hxp_error_pos_for validates the compiler's location against the filesystem;
# an unopenable file (pandoc's swept temp .tex) must degrade to the source with
# no position rather than send the editor to a line in a file that isn't there.
print -r -- "  [error jump target]"

epos() {
  local f l c
  IFS=$'\t' read -r f l c <<< "$(_hxp_error_pos_for "$1" "$2")"
  print -r -- "${f:t}|$l|$c"
}

print -r -- 'placeholder' >| "$work/main.tex"
check "pos resolves"     "main.tex|42|"  "$(epos "$work/main.tex" "$latex_log")"
check "helix hint"       "hx $work/main.tex:42"     "$(_hxp_editor_target_for_error helix "$work/main.tex" "$latex_log")"
check "micro hint"       "micro +42 $work/main.tex" "$(_hxp_editor_target_for_error micro "$work/main.tex" "$latex_log")"

rm -f -- "$work/main.tex"
check "pos falls back"   "gone.tex||"    "$(epos "$work/gone.tex" "$latex_log")"
check "helix hint bare"  "hx $work/gone.tex"    "$(_hxp_editor_target_for_error helix "$work/gone.tex" "$latex_log")"
check "micro hint bare"  "micro $work/gone.tex" "$(_hxp_editor_target_for_error micro "$work/gone.tex" "$latex_log")"

# ---- state file keying -------------------------------------------------
# hxp() writes the state file from zsh; hxp-jump and hxp-fwd find it from bash.
# Both digest the *absolute source path with no trailing newline* — if the two
# ever disagree, inverse search silently stops reaching the running editor.
print -r -- "  [state file]"

state_src="$work/doc.tex"
zsh_state="$(XDG_RUNTIME_DIR="$work"; _hxp_state_file "$state_src")"
bash_state="$work/hxp/$(printf '%s' "$state_src" | sha1sum | cut -d' ' -f1).state"
check "state key agrees" "$bash_state" "$zsh_state"

mkdir -p -- "${zsh_state:h}"
print -rl -- "src=$state_src" "editor=micro" >| "$zsh_state"
# A running session outranks the environment: an hxp_errs pane started without
# HXP_EDITOR must still print the command for the editor that holds the file.
check "session editor"   micro "$(XDG_RUNTIME_DIR="$work"; unset HXP_EDITOR; _hxp_session_editor "$state_src")"
rm -f -- "$zsh_state"
check "no session"       helix "$(XDG_RUNTIME_DIR="$work"; unset HXP_EDITOR; _hxp_session_editor "$state_src")"

if (( fail == 0 )); then
  print -r -- "PARSE TESTS PASSED"
  exit 0
else
  print -r -- "PARSE TESTS FAILED"
  exit 1
fi
