# ~/.zsh/hxp-lib.zsh
# Helpers for hxp / wpdf / hxp-compile. Sourced from .zshrc and from the
# ~/.local/bin/hxp-compile wrapper. Keep this file self-contained so the
# wrapper doesn't need to re-source the whole .zshrc on every recompile.

_hxp_need_cmd() { command -v "$1" >/dev/null 2>&1 }
_hxp_abs() { print -r -- "${1:A}" }

_hxp_viewer() {
  if [[ -n "$HXP_VIEWER" ]]; then print -r -- "$HXP_VIEWER"; return; fi
  if _hxp_need_cmd sioyek; then print -r -- sioyek
  else print -r -- zathura
  fi
}

# Find the project-root source for tex/typ. Falls back to the file itself.
_hxp_root_for() {
  local src="$1" ext="$2"
  case "$ext" in
    tex)
      if grep -q -E '^[[:space:]]*\\documentclass' -- "$src" 2>/dev/null; then
        print -r -- "$src"; return
      fi
      local cur="${src:h}" n
      while [[ -n "$cur" && "$cur" != "/" ]]; do
        for n in main.tex root.tex thesis.tex; do
          if [[ -f "$cur/$n" ]] && \
             grep -q -E '^[[:space:]]*\\documentclass' -- "$cur/$n" 2>/dev/null; then
            print -r -- "$cur/$n"; return
          fi
        done
        cur="${cur:h}"
      done
      print -r -- "$src"
      ;;
    typ)
      local cur="${src:h}"
      while [[ -n "$cur" && "$cur" != "/" ]]; do
        if [[ -f "$cur/main.typ" ]]; then print -r -- "$cur/main.typ"; return; fi
        if [[ -f "$cur/typst.toml" ]]; then
          [[ -f "$cur/main.typ" ]] && { print -r -- "$cur/main.typ"; return; }
          break
        fi
        cur="${cur:h}"
      done
      print -r -- "$src"
      ;;
    *) print -r -- "$src" ;;
  esac
}

# Write a minimal starter file based on the extension. Used by hxp() when
# the user passes a path that doesn't exist yet (nano/vim-style "editor
# creates the file" UX).
_hxp_scaffold() {
  local path="$1"
  local stem="${${path:t}:r}"
  local ext="${${path:t}:e}"
  local dir="${path:h}"

  [[ -d "$dir" ]] || mkdir -p -- "$dir" || return 1

  case "$ext" in
    md)
      {
        print -r -- "# ${stem}"
        print
        print
      } >| "$path"
      ;;
    tex)
      {
        print -r -- '\documentclass[11pt]{article}'
        print -r -- '\usepackage[utf8]{inputenc}'
        print -r -- '\usepackage{amsmath,amssymb}'
        print -r -- '\usepackage{hyperref}'
        print -r -- ''
        print -r -- "\\title{${stem}}"
        print -r -- '\author{}'
        print -r -- '\date{}'
        print -r -- ''
        print -r -- '\begin{document}'
        print -r -- '\maketitle'
        print -r -- ''
        print -r -- ''
        print -r -- '\end{document}'
      } >| "$path"
      ;;
    typ)
      {
        print -r -- '#set page(margin: 1in)'
        print -r -- '#set text(size: 11pt)'
        print -r -- ''
        print -r -- "= ${stem}"
        print -r -- ''
      } >| "$path"
      ;;
    *)
      : >| "$path"
      ;;
  esac
}

# Pick a CJK-capable font for xelatex/lualatex so Korean/Japanese/Chinese
# glyphs in markdown render instead of disappearing. Honors $HXP_CJK_FONT,
# otherwise probes fontconfig for the first available preferred font.
_hxp_cjk_font() {
  emulate -L zsh
  if [[ -n "$HXP_CJK_FONT" ]]; then
    print -r -- "$HXP_CJK_FONT"
    return 0
  fi
  _hxp_need_cmd fc-list || return 1

  local font
  for font in \
    'Noto Sans CJK KR' \
    'Noto Serif CJK KR' \
    'NanumGothic' \
    'NanumMyeongjo' \
    'Baekmuk Batang'
  do
    if fc-list | grep -qF -- "$font"; then
      print -r -- "$font"
      return 0
    fi
  done
  return 1
}

# First sibling .bib in the source's directory, if any.
_hxp_bib_for() {
  local src="$1"
  local dir="${src:h}"
  local -a bibs
  bibs=( "$dir"/*.bib(N) )
  (( ${#bibs[@]} == 0 )) && return
  print -r -- "${bibs[1]}"
}

# No-op: both viewers handle reload natively.
#   * zathura uses its own inotify watcher (`reload-file` / `file_changed`)
#     and re-renders on disk change — SIGHUP is NOT a reload signal in
#     zathura ≤ 0.5.4 (default action terminate; the process dies).
#   * sioyek reloads via `auto_reload_preference 1` in prefs_user.config.
# Kept as a stub so callers don't have to care which viewer they're driving.
_hxp_reload_viewer() {
  :
}

_hxp_extract_line() {
  local err_log="$1"
  local loc file line col
  loc="$(_hxp_error_location "$err_log" "")"
  IFS=$'\t' read -r file line col <<< "$loc"
  print -r -- "$line"
}

_hxp_resolve_error_file() {
  emulate -L zsh
  local fallback="$1" file="$2" candidate

  if [[ -z "$file" ]]; then
    print -r -- "$fallback"
    return
  fi

  if [[ -f "$file" ]]; then
    print -r -- "${file:A}"
    return
  fi

  if [[ "$file" != /* && -n "$fallback" ]]; then
    candidate="${fallback:h}/$file"
    if [[ -f "$candidate" ]]; then
      print -r -- "${candidate:A}"
      return
    fi
  fi

  print -r -- "$file"
}

_hxp_runaway_hint() {
  emulate -L zsh
  local err_log="$1" awk_bin=awk
  _hxp_need_cmd gawk && awk_bin=gawk

  "$awk_bin" '
    /^Runaway argument\?/ {
      if (getline > 0) {
        gsub(/\\ETC\..*/, "")
        gsub(/^[[:space:]{]+/, "")
        gsub(/[[:space:]]+$/, "")
        print
        exit
      }
    }
  ' "$err_log" 2>/dev/null
}

_hxp_line_from_hint() {
  emulate -L zsh
  local file="$1" hint="$2" line needle
  [[ -f "$file" && -n "$hint" ]] || return 0

  needle="$hint"
  [[ "$needle" == *". "* ]] && needle="${needle%%. *}."

  while (( ${#needle} >= 8 )); do
    line="$(grep -nF -- "$needle" "$file" 2>/dev/null | head -n 1 | cut -d: -f1)"
    if [[ -n "$line" ]]; then
      print -r -- "$line"
      return 0
    fi
    needle="${needle%?}"
  done
}

_hxp_error_location() {
  emulate -L zsh
  local err_log="$1" fallback="$2" awk_bin=awk loc file line col hint
  _hxp_need_cmd gawk && awk_bin=gawk

  loc="$("$awk_bin" '
    match($0, /^(.+\.tex):([0-9]+):/, m) {
      printf "%s\t%s\t\n", m[1], m[2]
      done=1
      exit
    }
    match($0, /-->[[:space:]]+(.+):([0-9]+):([0-9]+)/, m) {
      printf "%s\t%s\t%s\n", m[1], m[2], m[3]
      done=1
      exit
    }
    match($0, /^l\.[[:space:]]*([0-9]+)/, m) {
      printf "%s\t%s\t\n", file, m[1]
      done=1
      exit
    }
    match($0, /^<\*>[[:space:]]+(.+\.tex)[[:space:]]*$/, m) {
      file=m[1]
    }
    END {
      if (!done && file != "") printf "%s\t\t\n", file
    }
  ' "$err_log" 2>/dev/null)"

  IFS=$'\t' read -r file line col <<< "$loc"
  file="$(_hxp_resolve_error_file "$fallback" "$file")"

  if [[ -z "$line" ]]; then
    hint="$(_hxp_runaway_hint "$err_log")"
    line="$(_hxp_line_from_hint "$file" "$hint")"
  fi

  printf '%s\t%s\t%s\n' "$file" "$line" "$col"
}

_hxp_hx_target_for_error() {
  emulate -L zsh
  local src="$1" err_log="$2" loc file line col

  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r file line col <<< "$loc"

  if [[ -n "$line" && -f "$file" ]]; then
    print -r -- "${file}:${line}${col:+:$col}"
  else
    print -r -- "$src"
  fi
}

_hxp_error_extract() {
  emulate -L zsh
  local err_log="$1" awk_bin=awk
  _hxp_need_cmd gawk && awk_bin=gawk

  # Each trigger restarts the per-block budget so we don't cut off mid-error,
  # but we cap the *total* output so cascading latex errors can't run away.
  # The per-block window (40) is wide enough for one typst error stanza
  # (header + ┌─ + source + caret) or one latex error with l.<n> follow-up.
  "$awk_bin" '
    BEGIN { show=0; n=0; total=0; per=40; total_max=400 }
    /^Runaway argument\?/ { show=1; n=0 }
    /^! / { show=1; n=0 }
    /\.tex:[0-9]+:/ { show=1; n=0 }
    /^error:/ { show=1; n=0 }
    /^[[:space:]]*-->/ { show=1; n=0 }
    show {
      print
      n++
      total++
      if (n >= per) show=0
      if (total >= total_max) exit
    }
  ' "$err_log" 2>/dev/null
}

# Approximate count of distinct compile errors in the log. Used in summaries
# so the user knows whether to expect "fix one and recompile" or "many things
# broke, fix in batches". Latex tends to double-emit ("! Foo" + "file:N: Foo"),
# so we credit only one of those and accept the over/under near misses.
_hxp_error_count() {
  emulate -L zsh
  local err_log="$1" awk_bin=awk
  _hxp_need_cmd gawk && awk_bin=gawk

  "$awk_bin" '
    /^error:/        { typst++; next }
    /\.tex:[0-9]+:/  { texline++; next }
    /^! /            { texbang++; next }
    /^Runaway argument\?/ { runaway++; next }
    END {
      if (typst > 0)        { print typst; exit }
      if (texline > 0)      { print texline + runaway; exit }
      if (texbang > 0)      { print texbang + runaway; exit }
      if (runaway > 0)      { print runaway; exit }
      print 0
    }
  ' "$err_log" 2>/dev/null
}

_hxp_primary_error() {
  emulate -L zsh
  local err_log="$1" awk_bin=awk
  _hxp_need_cmd gawk && awk_bin=gawk

  "$awk_bin" '
    /Runaway argument\?/ { print; exit }
    /\.tex:[0-9]+:/ {
      sub(/^.*\.tex:[0-9]+:[[:space:]]*/, "")
      print
      exit
    }
    /^! / {
      sub(/^![[:space:]]*/, "")
      print
      exit
    }
    /^error:/ {
      print
      exit
    }
  ' "$err_log" 2>/dev/null
}

_hxp_source_line() {
  emulate -L zsh
  local file="$1" line="$2"
  [[ -f "$file" && "$line" == <-> ]] || return 0
  sed -n "${line}p" "$file" 2>/dev/null
}

_hxp_source_context() {
  emulate -L zsh
  local file="$1" line="$2" radius="${3:-6}" start end
  [[ -f "$file" && "$line" == <-> ]] || return 0

  start=$(( line - radius )); (( start < 1 )) && start=1
  end=$(( line + radius ))

  nl -ba "$file" 2>/dev/null | sed -n "${start},${end}p" | awk -v target="$line" '
    $1 == target { print ">>> " $0; next }
    { print "    " $0 }
  '
}

_hxp_write_error_md() {
  local src="$1" ext="$2" err_log="$3" err_md="$4" debug_tex="$5"
  local loc loc_file line col location extract primary source_line hx_target count count_label
  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r loc_file line col <<< "$loc"
  location="$loc_file"
  [[ -n "$line" ]] && location="${location}:${line}"
  [[ -n "$col" ]] && location="${location}:${col}"
  extract="$(_hxp_error_extract "$err_log")"
  primary="$(_hxp_primary_error "$err_log")"
  source_line="$(_hxp_source_line "$loc_file" "$line")"
  hx_target="$(_hxp_hx_target_for_error "$src" "$err_log")"
  count="$(_hxp_error_count "$err_log")"
  if [[ "$count" -gt 1 ]]; then
    # Plain hyphen (not em-dash) so pdflatex-only setups still render this
    # header — the error PDF must compile even when the doc-level pipeline
    # is what put us here.
    count_label="Compile failed - $count errors"
  else
    count_label="Compile failed"
  fi

  {
    print -r -- '---'
    print -r -- 'geometry: margin=0.75in'
    print -r -- 'header-includes: |'
    print -r -- '  \usepackage{hyperref}'
    print -r -- '  \usepackage{xcolor}'
    print -r -- '  \hypersetup{colorlinks=true,linkcolor=blue,urlcolor=blue}'
    print -r -- '---'
    print
    print -r -- '\begingroup'
    print -r -- '\setlength{\fboxsep}{8pt}'
    printf '\\colorbox{red!12}{\\parbox{\\dimexpr\\linewidth-2\\fboxsep}{\\Large\\bfseries %s}}\n' "$count_label"
    print -r -- '\endgroup'
    print
    print -r -- '# Look Here First'
    print
    if [[ -n "$primary" ]]; then
      echo "**Compiler says:** $primary"
      echo
    fi
    if [[ -n "$line" ]]; then
      echo "**Location:** [\`$location\`](file://$loc_file#$line)"
    else
      echo "**File:** [\`$loc_file\`](file://$loc_file)"
    fi
    echo
    echo "**Helix target:** \`$hx_target\`"
    echo

    if [[ -n "$source_line" ]]; then
      echo "## Suspect Line"
      echo '```'
      printf '%s | %s\n' "$line" "$source_line"
      echo '```'
      echo
    fi

    if [[ "$ext" == "tex" || "$ext" == "typ" ]]; then
      if [[ -n "$line" ]]; then
        echo "## Nearby Source"
        echo '```'
        _hxp_source_context "$loc_file" "$line"
        echo '```'
        echo
      fi
    fi

    echo "## Compiler Extract"
    echo '```'
    if [[ -n "$extract" ]]; then
      print -r -- "$extract"
    else
      tail -n 80 "$err_log"
    fi
    echo '```'

    if [[ "$ext" == "md" ]]; then
      echo
      echo "## Where this really is"
      echo "Pandoc PDF errors typically reference the generated LaTeX, not Markdown."
      if [[ -n "$line" ]]; then
        echo "- **LaTeX line:** [\`$debug_tex:$line\`](file://$debug_tex#$line)"
      fi

      if [[ -n "$line" && -f "$debug_tex" ]]; then
        local start end
        start=$(( line - 5 )); (( start < 1 )) && start=1
        end=$(( line + 5 ))
        echo
        echo "### LaTeX context (accurate)"
        echo '```'
        nl -ba "$debug_tex" | sed -n "${start},${end}p"
        echo '```'

        local mdline; mdline="$(_hxp_guess_md_line_from_tex "$src" "$debug_tex" "$line")"
        if [[ -n "$mdline" ]]; then
          local mstart mend
          mstart=$(( mdline - 5 )); (( mstart < 1 )) && mstart=1
          mend=$(( mdline + 5 ))
          echo
          echo "### Probable Markdown location (heuristic)"
          echo "Best guess: around [\`$src:$mdline\`](file://$src#$mdline)"
          echo '```'
          nl -ba "$src" | sed -n "${mstart},${mend}p"
          echo '```'
        fi
      fi
    fi
  } >| "$err_md"
}

_hxp_make_error_pdf() {
  local src="$1" ext="$2" err_log="$3" err_md="$4" temp_pdf="$5" debug_tex="$6"
  local -a pdf_engine

  _hxp_write_error_md "$src" "$ext" "$err_log" "$err_md" "$debug_tex"

  _hxp_need_cmd xelatex && pdf_engine=( --pdf-engine=xelatex )

  if pandoc -f markdown "${pdf_engine[@]}" "$err_md" -o "$temp_pdf" \
      --pdf-engine-opt=-interaction=nonstopmode \
      --pdf-engine-opt=-halt-on-error \
      --pdf-engine-opt=-file-line-error \
      >/dev/null 2>&1; then
    return 0
  fi

  pandoc -f text "${pdf_engine[@]}" "$err_log" -o "$temp_pdf" \
    --pdf-engine-opt=-interaction=nonstopmode \
    --pdf-engine-opt=-halt-on-error \
    --pdf-engine-opt=-file-line-error \
    >/dev/null 2>&1
}

_hxp_guess_md_line_from_tex() {
  local md="$1" tex="$2" tex_line="$3"

  [[ -z "$tex_line" || ! -f "$tex" || ! -f "$md" ]] && return 0

  local start end chunk sig
  start=$(( tex_line - 3 )); (( start < 1 )) && start=1
  end=$(( tex_line + 3 ))

  chunk="$(sed -n "${start},${end}p" "$tex" 2>/dev/null \
    | sed -E 's/\\[A-Za-z@]+(\*|)(\[[^]]*\])?(\{[^}]*\})?//g; s/[{}\\]/ /g; s/[[:space:]]+/ /g')"

  sig="$(print -r -- "$chunk" \
    | tr ' ' '\n' \
    | sed -E 's/[^[:alnum:]\-_.]//g' \
    | awk 'length($0)>=8 { if (length($0)>max) { max=length($0); best=$0 } } END{ print best }')"

  [[ -z "$sig" ]] && return 0

  grep -nF "$sig" "$md" 2>/dev/null | head -n 1 | cut -d: -f1
}

_hxp_compile_once() {
  emulate -L zsh
  setopt pipefail clobber
  local src="$1" ext="$2" dir="$3" stem="$4"
  local pdf="$5" temp_pdf="$6" err_log="$7" err_md="$8" debug_tex="$9" build_dir="${10}"

  rm -f -- "$temp_pdf"
  : >| "$err_log"

  local ok=1
  local base="${src:t}"

  # Project-aware root for tex/typ; bib auto-detection.
  local root_src; root_src="$(_hxp_root_for "$src" "$ext")"
  local root_dir="${root_src:h}"
  local root_base="${root_src:t}"
  local root_stem="${root_base:r}"
  local bib; bib="$(_hxp_bib_for "$root_src")"

  case "$ext" in
    md)
      local -a pdf_vars
      pdf_vars=( -V colorlinks=true -V linkcolor=blue -V urlcolor=blue )

      local -a cite_args
      if [[ -n "$bib" ]]; then
        cite_args=( --citeproc --bibliography="$bib" )
      fi

      # pandoc's default PDF engine is pdflatex, which chokes on any non-ASCII
      # input (Unicode → "character not set up for use with LaTeX"). Prefer
      # xelatex/lualatex when present so Korean, emoji, etc. compile cleanly.
      local -a pdf_engine
      if _hxp_need_cmd xelatex; then
        pdf_engine=( --pdf-engine=xelatex )
      elif _hxp_need_cmd lualatex; then
        pdf_engine=( --pdf-engine=lualatex )
      fi

      # When using a Unicode-aware engine, set CJKmainfont so Korean/Japanese/
      # Chinese glyphs actually render. Skip if the doc already declares one
      # in its YAML — user intent wins over our default.
      if (( ${#pdf_engine[@]} > 0 )) \
         && ! grep -q -E '^[[:space:]]*CJKmainfont[[:space:]]*:' -- "$src" 2>/dev/null; then
        local cjk_font; cjk_font="$(_hxp_cjk_font)"
        [[ -n "$cjk_font" ]] && pdf_vars+=( -V "CJKmainfont=$cjk_font" )
      fi

      if (
        cd -- "$dir" &&
        pandoc -f markdown "${pdf_engine[@]}" "${pdf_vars[@]}" "${cite_args[@]}" "$base" -o "$temp_pdf" \
          --pdf-engine-opt=-synctex=1 \
          --pdf-engine-opt=-interaction=nonstopmode \
          --pdf-engine-opt=-halt-on-error \
          --pdf-engine-opt=-file-line-error \
          >"$err_log" 2>&1
      ); then
        ok=0
      else
        (
          cd -- "$dir" &&
          pandoc -f markdown "${cite_args[@]}" -s -t latex "$base" -o "$debug_tex" >/dev/null 2>&1
        )
      fi
      ;;

    typ)
      # `typst compile` doesn't emit synctex (typst doesn't support it).
      # Use --root so cross-file `#import`s resolve from the project root.
      if typst compile --root "$root_dir" "$root_src" "$pdf" >"$err_log" 2>&1; then
        rm -f -- "$err_md" "$debug_tex"
        _hxp_reload_viewer
        return 0
      fi
      ;;

    tex)
      mkdir -p -- "$build_dir"
      local -a bib_args
      [[ -n "$bib" ]] && bib_args=( -bibtex )
      if latexmk -pdf -synctex=1 -interaction=nonstopmode -halt-on-error \
          -file-line-error \
          "${bib_args[@]}" \
          -outdir="$build_dir" -auxdir="$build_dir" \
          "$root_src" >"$err_log" 2>&1; then
        if [[ -f "$build_dir/$root_stem.pdf" ]]; then
          mv -f -- "$build_dir/$root_stem.pdf" "$temp_pdf"
          if [[ -f "$build_dir/$root_stem.synctex.gz" ]]; then
            cp -f -- "$build_dir/$root_stem.synctex.gz" "$dir/$root_stem.synctex.gz" 2>/dev/null
          fi
          ok=0
        fi
      fi
      ;;

    *)
      print -u2 -- "hxp/wpdf: unsupported extension: $ext"
      return 2
      ;;
  esac

  if [[ $ok -eq 0 && -s "$temp_pdf" ]]; then
    mv -f -- "$temp_pdf" "$pdf"
    rm -f -- "$err_md" "$debug_tex"
    _hxp_reload_viewer
    return 0
  fi

  if _hxp_make_error_pdf "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex"; then
    if [[ -s "$temp_pdf" ]]; then
      mv -f -- "$temp_pdf" "$pdf"
      _hxp_reload_viewer
    fi
  fi
  rm -f -- "$temp_pdf"
  return 1
}

# ---------- hxp_errs: live terminal-pane error display ----------
# Pair this with hxp in a separate tmux pane / terminal:
#   pane 1 (or full terminal): hxp file.tex
#   pane 2:                    hxp_errs file.tex
# Re-renders compile state on each save so errors land in your eye-line
# instead of requiring a glance at the PDF viewer.

# Render the current compile state (OK / ERROR + first error) into the
# current terminal. Clears and homes the cursor first so successive renders
# overwrite cleanly. Kept in the lib so hxp_errs can call it on each tick.
_hxp_render_errs() {
  emulate -L zsh
  local err_log="$1" err_md="$2" src="$3"
  local C_OK=$'\033[1;32m' C_ERR=$'\033[1;31m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_RST=$'\033[0m'

  printf '\033[2J\033[H'
  local ts; ts="$(date +%H:%M:%S)"

  if [[ ! -e "$err_md" ]]; then
    printf '%s✓ OK%s  %s\n\n  %s\n' "$C_OK" "$C_RST" "$ts" "$src"
    return 0
  fi

  printf '%s✗ ERROR%s  %s\n\n  %s\n\n' "$C_ERR" "$C_RST" "$ts" "$src"

  local count; count="$(_hxp_error_count "$err_log")"
  [[ "$count" -gt 1 ]] && printf '  %s%s errors%s\n\n' "$C_BOLD" "$count" "$C_RST"

  local primary; primary="$(_hxp_primary_error "$err_log")"
  [[ -n "$primary" ]] && printf '  %s\n' "$primary"

  local loc file line col
  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r file line col <<< "$loc"

  # For markdown→pdf failures the error file is pandoc's temp .tex (already
  # garbage-collected). Only show "at <file>:<line>" when the file is real
  # and on disk — otherwise the line number is meaningful only inside that
  # ghost tex, and would just confuse the user.
  if [[ -n "$line" && -f "$file" ]]; then
    printf '  %sat%s %s:%s%s\n' "$C_DIM" "$C_RST" "$file" "$line" "${col:+:$col}"
    local source_line; source_line="$(_hxp_source_line "$file" "$line")"
    [[ -n "$source_line" ]] && printf '\n  %s|%s %s\n' "$C_DIM" "$C_RST" "$source_line"
  fi

  local hx_target; hx_target="$(_hxp_hx_target_for_error "$src" "$err_log")"
  printf '\n  %shx %s%s\n' "$C_DIM" "$hx_target" "$C_RST"
}

hxp_errs() {
  emulate -L zsh
  setopt pipefail

  local src="$1"
  [[ -z "$src" ]] && { print -u2 -- "usage: hxp_errs <file.{md,tex,typ}>"; return 2; }
  [[ ! -f "$src" ]] && { print -u2 -- "hxp_errs: not found: $src"; return 2; }
  _hxp_need_cmd inotifywait || { print -u2 -- "hxp_errs: missing inotifywait (install inotify-tools)"; return 2; }

  src="$(_hxp_abs "$src")"
  local dir="${src:h}"
  local stem="${${src:t}:r}"
  local err_log="$dir/.${stem}.error.log"
  local err_md="$dir/.${stem}.error.md"
  local pdf="$dir/$stem.pdf"

  _hxp_render_errs "$err_log" "$err_md" "$src"

  # Watch the source's directory for the touch-points _hxp_compile_once
  # writes on each compile. Crucially we include `delete` — the FAIL→OK
  # transition removes err_md *after* writing err_log, so without watching
  # the deletion we'd render the stale ERROR state and never refresh.
  local changed _drain
  inotifywait -m -q -e close_write -e moved_to -e create -e delete \
      --format '%w%f' "$dir" 2>/dev/null \
    | while IFS= read -r changed; do
        case "$changed" in
          "$err_log"|"$err_md"|"$pdf") ;;
          *) continue ;;
        esac
        # Debounce: a single compile fires 5-6 events in quick succession
        # (truncate, write, mv, rm). Drain any that arrive within 200ms of
        # the trigger so we render the *final* state once, not each
        # intermediate state.
        while IFS= read -r -t 0.2 _drain 2>/dev/null; do :; done
        _hxp_render_errs "$err_log" "$err_md" "$src"
      done
}
