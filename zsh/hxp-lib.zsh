# Compile and search helpers; keep independent of .zshrc.

_hxp_need_cmd() { command -v "$1" >/dev/null 2>&1 }
_hxp_abs() { print -r -- "${1:A}" }

# Keep awk programs POSIX-compatible; HXP_AWK selects the test binary.
_hxp_awk() {
  if [[ -n "$HXP_AWK" ]]; then print -r -- "$HXP_AWK"; return; fi
  if _hxp_need_cmd gawk; then print -r -- gawk; else print -r -- awk; fi
}

_hxp_viewer() {
  if [[ -n "$HXP_VIEWER" ]]; then print -r -- "$HXP_VIEWER"; return; fi
  if _hxp_need_cmd sioyek; then print -r -- sioyek
  else print -r -- zathura
  fi
}

_hxp_editor() {
  [[ "${${HXP_EDITOR:-}:l}" == "micro" ]] && { print -r -- micro; return; }
  print -r -- helix
}

_hxp_editor_bin() {
  case "$1" in
    micro) print -r -- micro ;;
    *)     print -r -- hx ;;
  esac
}

# Emit editor argv, one argument per line; omit empty positions.
_hxp_editor_argv() {
  emulate -L zsh
  local editor="$1" file="$2" line="$3" col="$4"
  shift 4

  case "$editor" in
    micro)
      print -r -- micro
      [[ -n "$line" ]] && print -r -- "+${line}${col:+:$col}"
      print -r -- "$file"
      ;;
    *)
      print -r -- hx
      if [[ -n "$line" ]]; then
        print -r -- "${file}:${line}${col:+:$col}"
      else
        print -r -- "$file"
      fi
      ;;
  esac

  local f
  for f in "$@"; do print -r -- "$f"; done
}

_hxp_editor_open() {
  emulate -L zsh
  # Avoid local argv: zsh aliases it to the positional parameters.
  local -a cmd
  cmd=( "${(@f)$(_hxp_editor_argv "$@")}" )
  "${cmd[@]}"
}

# Hash without a trailing newline to match the bash search helpers.
_hxp_state_file() {
  emulate -L zsh
  local key; key="$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)"
  print -r -- "${XDG_RUNTIME_DIR:-/tmp}/hxp/$key.state"
}

# Use the session editor for error hints, then fall back to HXP_EDITOR.
_hxp_session_editor() {
  emulate -L zsh
  local sf k v
  sf="$(_hxp_state_file "$1")"
  if [[ -r "$sf" ]]; then
    while IFS='=' read -r k v; do
      [[ "$k" == "editor" && -n "$v" ]] && { print -r -- "$v"; return 0; }
    done < "$sf"
  fi
  _hxp_editor
}

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

# Included sources share the root PDF.
_hxp_pdf_for() {
  emulate -L zsh
  local root_src; root_src="$(_hxp_root_for "$1" "$2")"
  print -r -- "${root_src:r}.pdf"
}

_hxp_scaffold() {
  local src="$1"
  local stem="${${src:t}:r}"
  local ext="${${src:t}:e}"
  local dir="${src:h}"

  [[ -d "$dir" ]] || mkdir -p -- "$dir" || return 1

  case "$ext" in
    md)
      {
        print -r -- "# ${stem}"
        print
        print
      } >| "$src"
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
      } >| "$src"
      ;;
    typ)
      {
        print -r -- '#set page(margin: 1in)'
        print -r -- '#set text(size: 11pt)'
        print -r -- ''
        print -r -- "= ${stem}"
        print -r -- ''
      } >| "$src"
      ;;
    *)
      : >| "$src"
      ;;
  esac
}

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

_hxp_bib_for() {
  local src="$1"
  local dir="${src:h}"
  local -a bibs
  bibs=( "$dir"/*.bib(N) )
  (( ${#bibs[@]} == 0 )) && return
  print -r -- "${bibs[1]}"
}

# Only frontmatter keys override defaults; ignore matches in body text.
_hxp_md_declares_key() {
  emulate -L zsh
  local src="$1" key="$2" awk_bin
  [[ -f "$src" && -n "$key" ]] || return 1
  awk_bin="$(_hxp_awk)"

  "$awk_bin" -v key="$key" '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^(---|\.\.\.)[[:space:]]*$/ { exit }
    fm && $0 ~ "^[[:space:]]*" key "[[:space:]]*:" { found = 1; exit }
    END { exit !found }
  ' "$src" 2>/dev/null
}

# Source and bibliography extensions for both watch backends.
_hxp_watch_exts() {
  case "$1" in
    md)  print -r -- 'md,bib' ;;
    tex) print -r -- 'tex,bib,sty,cls' ;;
    typ) print -r -- 'typ,bib,yml,yaml' ;;
    *)   print -r -- "$1" ;;
  esac
}

# Exclude generated sources to prevent rebuild loops; match watchexec rules.
_hxp_watch_match() {
  emulate -L zsh
  local ext="$1" path="$2" cbase="${2:t}"
  [[ "$cbase" == .* ]] && return 1                # our dot-prefixed artifacts
  [[ "$path" == *.hxp_build_*/* ]] && return 1     # build-dir churn
  local exts=",$(_hxp_watch_exts "$ext"),"
  [[ "$exts" == *",${cbase:e},"* ]]
}

# Viewers reload natively; SIGHUP can terminate Zathura.
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
  local err_log="$1" awk_bin
  awk_bin="$(_hxp_awk)"

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
  local err_log="$1" fallback="$2" awk_bin loc file line col hint
  awk_bin="$(_hxp_awk)"

  # Parse LaTeX and Typst locations with POSIX awk.
  loc="$("$awk_bin" '
    # LaTeX: file.tex:line:
    /\.tex:[0-9]+:/ {
      if (match($0, /\.tex:[0-9]+:/)) {
        f = substr($0, 1, RSTART + 3)
        n = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", n)
        printf "%s\t%s\t\n", f, n
        done = 1; exit
      }
    }
    # Typst: file.typ:line:column
    /:[0-9]+:[0-9]+[[:space:]]*$/ {
      s = $0; sub(/[[:space:]]+$/, "", s)
      c = s; sub(/^.*:/, "", c)
      sub(/:[0-9]+$/, "", s)
      l = s; sub(/^.*:/, "", l)
      sub(/:[0-9]+$/, "", s)
      f = s; sub(/^.*[[:space:]]/, "", f)
      printf "%s\t%s\t%s\n", f, l, c
      done = 1; exit
    }
    # TeX: l.NN, using the prior <*> filename.
    /^l\.[[:space:]]*[0-9]+/ {
      n = $0; sub(/^l\.[[:space:]]*/, "", n); sub(/[^0-9].*$/, "", n)
      printf "%s\t%s\t\n", file, n
      done = 1; exit
    }
    /^<\*>[[:space:]]+.+\.tex[[:space:]]*$/ {
      f = $0; sub(/^<\*>[[:space:]]+/, "", f); sub(/[[:space:]]+$/, "", f)
      file = f
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

# Emit file<TAB>line<TAB>col; discard locations in missing files.
_hxp_error_pos_for() {
  emulate -L zsh
  local src="$1" err_log="$2" loc file line col

  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r file line col <<< "$loc"

  if [[ -n "$line" && -f "$file" ]]; then
    printf '%s\t%s\t%s\n' "$file" "$line" "$col"
  else
    printf '%s\t\t\n' "$src"
  fi
}

_hxp_editor_target_for_error() {
  emulate -L zsh
  local editor="$1" src="$2" err_log="$3" file line col
  local -a cmd

  IFS=$'\t' read -r file line col <<< "$(_hxp_error_pos_for "$src" "$err_log")"
  cmd=( "${(@f)$(_hxp_editor_argv "$editor" "$file" "$line" "$col")}" )
  print -r -- "${cmd[*]}"
}

_hxp_error_extract() {
  emulate -L zsh
  local err_log="$1" awk_bin
  awk_bin="$(_hxp_awk)"

  # Cap each error block and the total extract.
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

# Approximate error count; avoid double-counting LaTeX diagnostics.
_hxp_error_count() {
  emulate -L zsh
  local err_log="$1" awk_bin
  awk_bin="$(_hxp_awk)"

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
  local err_log="$1" awk_bin
  awk_bin="$(_hxp_awk)"

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
  local loc loc_file line col location extract primary source_line editor_cmd count count_label
  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r loc_file line col <<< "$loc"
  location="$loc_file"
  [[ -n "$line" ]] && location="${location}:${line}"
  [[ -n "$col" ]] && location="${location}:${col}"
  extract="$(_hxp_error_extract "$err_log")"
  primary="$(_hxp_primary_error "$err_log")"
  source_line="$(_hxp_source_line "$loc_file" "$line")"
  editor_cmd="$(_hxp_editor_target_for_error "$(_hxp_session_editor "$src")" "$src" "$err_log")"
  count="$(_hxp_error_count "$err_log")"
  if [[ "$count" -gt 1 ]]; then
    # ASCII hyphen keeps the header compatible with pdflatex.
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
    echo "**Editor target:** \`$editor_cmd\`"
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

# Render raw logs with Typst; no LaTeX dependency or markup escaping.
_hxp_make_typst_error_pdf() {
  emulate -L zsh
  local err_log="$1" temp_pdf="$2"
  _hxp_need_cmd typst || return 1
  [[ -s "$err_log" ]] || return 1

  local root="${err_log:h}" base="${err_log:t}"
  local err_typ="${temp_pdf:r}.errdoc.typ"
  local count heading
  count="$(_hxp_error_count "$err_log")"
  heading="Compile failed"
  [[ "$count" -gt 1 ]] && heading="Compile failed - $count errors"

  {
    print -r -- '#set page(margin: 0.75in)'
    print -r -- '#set text(size: 10pt)'
    print -r -- "#block(width: 100%, inset: 10pt, radius: 4pt, fill: rgb(\"#fdecea\"), stroke: rgb(\"#dd3333\"))[#text(size: 15pt, weight: \"bold\", fill: rgb(\"#bb0000\"))[${heading}]]"
    print -r -- '#v(8pt)'
    printf '#raw(read("%s"), block: true)\n' "$base"
  } >| "$err_typ"

  typst compile --root "$root" "$err_typ" "$temp_pdf" >/dev/null 2>&1
  local rc=$?
  rm -f -- "$err_typ"
  return $rc
}

_hxp_make_error_pdf() {
  local src="$1" ext="$2" err_log="$3" err_md="$4" temp_pdf="$5" debug_tex="$6"
  local -a pdf_engine

  _hxp_write_error_md "$src" "$ext" "$err_log" "$err_md" "$debug_tex"

  if [[ "$ext" == "typ" ]] && _hxp_make_typst_error_pdf "$err_log" "$temp_pdf"; then
    return 0
  fi

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
  emulate -L zsh
  _hxp_need_cmd hxp-mdline || return 0
  hxp-mdline "$1" "$2" "$3"
}

# Remove scratch files, preserving the output PDF.
_hxp_sweep_artifacts() {
  emulate -L zsh
  local temp_pdf="$1" err_log="$2" err_md="$3" debug_tex="$4" synctex_gz="$5" build_dir="$6"
  rm -f -- "$temp_pdf" "${temp_pdf:r}.watch.pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" 2>/dev/null
  [[ -n "$build_dir" ]] && rm -rf -- "$build_dir" 2>/dev/null
  return 0
}

# Publish a completed watch snapshot or render its errors.
_hxp_typst_render_state() {
  emulate -L zsh
  local state="$1" buf="$2" src="$3" ext="$4" err_log="$5" err_md="$6" temp_pdf="$7" debug_tex="$8" pdf="$9"
  local watch_pdf="${10:-}"
  : >| "$err_log"
  if [[ "$state" == "ok" ]]; then
    if [[ -n "$watch_pdf" ]]; then
      [[ -s "$watch_pdf" ]] || return 1
      cp -f -- "$watch_pdf" "$temp_pdf" && mv -f -- "$temp_pdf" "$pdf" || return 1
    fi
    rm -f -- "$err_md"
    return 0
  fi
  print -rn -- "$buf" >> "$err_log"
  if _hxp_make_error_pdf "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex"; then
    [[ -s "$temp_pdf" ]] && mv -f -- "$temp_pdf" "$pdf"
  fi
  rm -f -- "$temp_pdf"
  return 0
}

# Publish success immediately; debounce error diagnostics with zselect.
_hxp_typst_watch_render() {
  emulate -L zsh
  local src="$1" ext="$2" err_log="$3" err_md="$4" temp_pdf="$5" debug_tex="$6" pdf="$7"
  local watch_pdf="${8:-}"

  if ! zmodload zsh/zselect 2>/dev/null; then
    # Without zselect, preserve diagnostics only.
    cat >> "$err_log"
    return 0
  fi

  local line buf="" state="" to
  while true; do
    [[ -n "$state" ]] && to=60 || to=6000
    if zselect -t "$to" -r 0; then
      IFS= read -r line || break              # fd readable but empty -> EOF
      case "$line" in
        *"] compiling "*)            buf=""; state="" ;;   # new cycle: reset
        *"compiled with errors"*)    state="fail" ;;
        *"compiled successfully"*|*"compiled with warning"*)
          _hxp_typst_render_state ok "$buf" \
            "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
          state=""; buf=""
          ;;
        watching\ *|"writing to "*|"") ;;                  # watch chatter
        *)                           buf+="$line"$'\n' ;;  # diagnostic
      esac
    else
      [[ -n "$state" ]] && _hxp_typst_render_state "$state" "$buf" \
        "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
      state=""; buf=""
    fi
  done
  [[ -n "$state" ]] && _hxp_typst_render_state "$state" "$buf" \
    "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
  return 0
}

_hxp_compile_once() {
  emulate -L zsh
  setopt pipefail clobber
  local -x PATH="/usr/bin:$PATH"  # Conda's Pandoc 2.12 ignores the enabled math syntax.
  local src="$1" ext="$2" dir="$3" stem="$4"
  local pdf="$5" temp_pdf="$6" err_log="$7" err_md="$8" debug_tex="$9" build_dir="${10}"

  rm -f -- "$temp_pdf"
  : >| "$err_log"

  local ok=1
  local base="${src:t}"

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
      if _hxp_md_declares_key "$src" bibliography; then
        cite_args=( --citeproc )
      elif [[ -n "$bib" ]]; then
        cite_args=( --citeproc --bibliography="$bib" )
      fi

      if ! _hxp_md_declares_key "$src" CJKmainfont; then
        local cjk_font; cjk_font="$(_hxp_cjk_font)"
        [[ -n "$cjk_font" ]] && pdf_vars+=( -V "CJKmainfont=$cjk_font" )
      fi

      # Normalize bare margins; empty HXP_MD_MARGIN keeps class defaults.
      local md_margin="${HXP_MD_MARGIN-0.75in}"
      if [[ -n "$md_margin" ]] && ! _hxp_md_declares_key "$src" geometry; then
        [[ "$md_margin" == *=* ]] || md_margin="margin=$md_margin"
        pdf_vars+=( -V "geometry=$md_margin" )
      fi

      if _hxp_need_cmd latexmk; then
        # SyncTeX needs the .hxp.tex intermediate; xelatex forbids dotfile outputs.
        mkdir -p -- "$build_dir"
        local synctex_tex="$build_dir/${stem}.hxp.tex"
        if (
          cd -- "$dir" &&
          pandoc -f markdown+tex_math_single_backslash "${pdf_vars[@]}" "${cite_args[@]}" \
            -s -t latex "$base" -o "$synctex_tex" \
            >"$err_log" 2>&1
        ); then
          debug_tex="$synctex_tex"
          local -a latexmk_engine
          if _hxp_need_cmd xelatex; then
            latexmk_engine=( -xelatex )
          elif _hxp_need_cmd lualatex; then
            latexmk_engine=( -lualatex )
          else
            latexmk_engine=( -pdf )
          fi

          if (
            cd -- "$dir" &&
            latexmk "${latexmk_engine[@]}" -synctex=1 \
                -interaction=nonstopmode -halt-on-error -file-line-error \
                -outdir="$build_dir" -auxdir="$build_dir" \
                "$synctex_tex" >>"$err_log" 2>&1
          ); then
            local build_stem="${${synctex_tex:t}:r}"
            if [[ -f "$build_dir/$build_stem.pdf" ]]; then
              mv -f -- "$build_dir/$build_stem.pdf" "$temp_pdf"
              if [[ -f "$build_dir/$build_stem.synctex.gz" ]]; then
                local pdf_base="${${pdf:t}:r}"
                cp -f -- "$build_dir/$build_stem.synctex.gz" \
                  "${pdf:h}/$pdf_base.synctex.gz" 2>/dev/null
              fi
              ok=0
            fi
          fi
        else
          debug_tex="$synctex_tex"
        fi
      else
        # Direct Pandoc fallback has no working SyncTeX.
        local -a pdf_engine
        if _hxp_need_cmd xelatex; then
          pdf_engine=( --pdf-engine=xelatex )
        elif _hxp_need_cmd lualatex; then
          pdf_engine=( --pdf-engine=lualatex )
        fi

        if (
          cd -- "$dir" &&
          pandoc -f markdown+tex_math_single_backslash "${pdf_engine[@]}" "${pdf_vars[@]}" "${cite_args[@]}" "$base" -o "$temp_pdf" \
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
            pandoc -f markdown+tex_math_single_backslash "${cite_args[@]}" -s -t latex "$base" -o "$debug_tex" >/dev/null 2>&1
          )
        fi
      fi
      ;;

    typ)
      if typst compile --root "$root_dir" "$root_src" "$temp_pdf" >"$err_log" 2>&1; then
        ok=0
      fi
      ;;

    tex)
      mkdir -p -- "$build_dir"
      local -a bib_args
      [[ -n "$bib" ]] && bib_args=( -bibtex )
      if (
        cd -- "$root_dir" &&
        latexmk -pdf -synctex=1 -interaction=nonstopmode -halt-on-error \
          -file-line-error \
          "${bib_args[@]}" \
          -outdir="$build_dir" -auxdir="$build_dir" \
          "$root_src" >"$err_log" 2>&1
      ); then
        if [[ -f "$build_dir/$root_stem.pdf" ]]; then
          mv -f -- "$build_dir/$root_stem.pdf" "$temp_pdf"
          if [[ -f "$build_dir/$root_stem.synctex.gz" ]]; then
            # Sidecars belong beside the root PDF, even for included sources.
            cp -f -- "$build_dir/$root_stem.synctex.gz" "${pdf:h}/$root_stem.synctex.gz" 2>/dev/null
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
    rm -f -- "$err_md"
    # Retain Markdown intermediates for inverse search.
    [[ "$ext" != "md" ]] && rm -f -- "$debug_tex"
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

  # Pandoc may reference a deleted temporary .tex file.
  if [[ -n "$line" && -f "$file" ]]; then
    printf '  %sat%s %s:%s%s\n' "$C_DIM" "$C_RST" "$file" "$line" "${col:+:$col}"
    local source_line; source_line="$(_hxp_source_line "$file" "$line")"
    [[ -n "$source_line" ]] && printf '\n  %s|%s %s\n' "$C_DIM" "$C_RST" "$source_line"
  fi

  local cmd
  cmd="$(_hxp_editor_target_for_error "$(_hxp_session_editor "$src")" "$src" "$err_log")"
  printf '\n  %s%s%s\n' "$C_DIM" "$cmd" "$C_RST"
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
  local pdf; pdf="$(_hxp_pdf_for "$src" "${src:e}")"

  _hxp_render_errs "$err_log" "$err_md" "$src"

  # Watch deletions: removing err_md signals error recovery.
  local changed _drain
  inotifywait -m -q -e close_write -e moved_to -e create -e delete \
      --format '%w%f' "$dir" 2>/dev/null \
    | while IFS= read -r changed; do
        case "$changed" in
          "$err_log"|"$err_md"|"$pdf") ;;
          *) continue ;;
        esac
        # Drain related events before rendering the final state.
        while IFS= read -r -t 0.2 _drain 2>/dev/null; do :; done
        _hxp_render_errs "$err_log" "$err_md" "$src"
      done
}

_hxp_doctor_row() {
  emulate -L zsh
  local name="$1" st="$2" detail="$3" mark
  local C_OK=$'\033[1;32m' C_NO=$'\033[1;31m' C_OPT=$'\033[1;33m' C_DIM=$'\033[2m' C_RST=$'\033[0m'
  case "$st" in
    ok)  mark="${C_OK}✓${C_RST}" ;;
    opt) mark="${C_OPT}○${C_RST}" ;;
    *)   mark="${C_NO}✗${C_RST}" ;;
  esac
  printf '  %s %-12s %s%s%s\n' "$mark" "$name" "$C_DIM" "$detail" "$C_RST"
}

_hxp_doctor() {
  emulate -L zsh
  local C_H=$'\033[1m' C_R=$'\033[0m' t viewer cjk editor editor_bin

  editor="$(_hxp_editor)"
  editor_bin="$(_hxp_editor_bin "$editor")"

  print -r -- "${C_H}hxp doctor${C_R}"
  print

  print -r -- "${C_H}Required${C_R}"
  for t in zsh pandoc inotifywait; do
    if _hxp_need_cmd "$t"; then _hxp_doctor_row "$t" ok "$(command -v "$t")"
    else _hxp_doctor_row "$t" miss "MISSING — required"; fi
  done
  if _hxp_need_cmd "$editor_bin"; then
    _hxp_doctor_row "$editor_bin" ok "active editor ($editor) — $(command -v "$editor_bin")"
  else
    _hxp_doctor_row "$editor_bin" miss "MISSING — the active editor ($editor)"
  fi
  if [[ -n "${HXP_EDITOR:-}" && "${${HXP_EDITOR:-}:l}" != (helix|hx|micro) ]]; then
    _hxp_doctor_row HXP_EDITOR opt "\"$HXP_EDITOR\" unrecognised — using helix"
  fi

  print
  print -r -- "${C_H}Compilers${C_R}"
  if _hxp_need_cmd latexmk; then _hxp_doctor_row latexmk ok "tex + md two-step synctex"
  else _hxp_doctor_row latexmk opt "absent — md uses pandoc-direct (no inverse search); .tex off"; fi
  if _hxp_need_cmd xelatex; then _hxp_doctor_row xelatex ok "unicode/CJK pdf engine"
  elif _hxp_need_cmd lualatex; then _hxp_doctor_row lualatex ok "unicode pdf engine"
  else _hxp_doctor_row xelatex opt "absent — CJK md may drop glyphs"; fi
  if _hxp_need_cmd typst; then _hxp_doctor_row typst ok "$(typst --version 2>/dev/null)"
  else _hxp_doctor_row typst opt "absent — .typ disabled"; fi

  print
  print -r -- "${C_H}Viewer${C_R}"
  viewer="$(_hxp_viewer)"
  if _hxp_need_cmd "$viewer"; then _hxp_doctor_row "$viewer" ok "active viewer"
  else _hxp_doctor_row "$viewer" miss "selected but not installed"; fi

  print
  print -r -- "${C_H}Watch / reload${C_R}"
  if _hxp_need_cmd watchexec && [[ "$HXP_NO_WATCHEXEC" != "1" ]]; then
    _hxp_doctor_row watchexec ok "debounced watch loop"
  else
    _hxp_doctor_row watchexec opt "using inotifywait fallback"
  fi

  print
  print -r -- "${C_H}Inverse search (PDF -> editor)${C_R}"
  if _hxp_need_cmd hxp-jump; then _hxp_doctor_row hxp-jump ok "$(command -v hxp-jump)"
  else _hxp_doctor_row hxp-jump miss "not on PATH — viewers can't reverse-search"; fi
  if _hxp_need_cmd hxp-mdline; then _hxp_doctor_row hxp-mdline ok "md <- tex line mapping"
  else _hxp_doctor_row hxp-mdline opt "absent — md location/inverse-search degraded"; fi
  if _hxp_need_cmd tmux; then _hxp_doctor_row tmux ok "in-place jumps when hxp runs in tmux"
  else _hxp_doctor_row tmux opt "absent — no tmux send-keys path"; fi
  if _hxp_need_cmd xdotool; then _hxp_doctor_row xdotool ok "X11 keystroke fallback (no tmux)"
  else _hxp_doctor_row xdotool opt "absent — jumps spawn a fresh $editor_bin without tmux"; fi

  print
  print -r -- "${C_H}Forward search (editor -> PDF)${C_R}"
  if _hxp_need_cmd hxp-fwd; then _hxp_doctor_row hxp-fwd ok "$(command -v hxp-fwd)"
  else _hxp_doctor_row hxp-fwd opt "not on PATH — bind C-l in $editor to enable"; fi
  if [[ "$editor" == "micro" ]]; then
    local mplug="$HOME/.config/micro/plug/hxpfwd/hxpfwd.lua"
    if [[ -e "$mplug" ]]; then _hxp_doctor_row hxpfwd.lua ok "micro plugin — bind \"command:hxpfwd\""
    else _hxp_doctor_row hxpfwd.lua opt "absent — run install.sh; micro has no forward search without it"; fi
  fi
  if _hxp_need_cmd hxp-texline; then _hxp_doctor_row hxp-texline ok "md -> tex line mapping"
  else _hxp_doctor_row hxp-texline opt "absent — md forward search raises the viewer only"; fi
  if _hxp_need_cmd wmctrl; then _hxp_doctor_row wmctrl ok "focuses the window showing this PDF"
  else _hxp_doctor_row wmctrl opt "absent — sioyek may sync the wrong window"; fi
  if _hxp_need_cmd hxp-typtext; then _hxp_doctor_row hxp-typtext ok "typ text-search phrases (no synctex)"
  else _hxp_doctor_row hxp-typtext opt "absent — typ forward search raises the viewer only"; fi
  if _hxp_need_cmd pdftotext; then _hxp_doctor_row pdftotext ok "locates the page for typ text search"
  else _hxp_doctor_row pdftotext opt "absent — typ forward search raises the viewer only"; fi
  if _hxp_need_cmd gdbus; then _hxp_doctor_row gdbus ok "pages a running zathura for typ"
  else _hxp_doctor_row gdbus opt "absent — typ + zathura raises the viewer only"; fi

  print
  print -r -- "${C_H}Window tiling${C_R}"
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    _hxp_doctor_row session opt "wayland — external tiling unsupported"
  else
    _hxp_doctor_row session ok "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"
  fi
  if [[ "$HXP_NO_TILE" == "1" ]]; then
    _hxp_doctor_row tiling opt "HXP_NO_TILE=1 — disabled"
  else
    if _hxp_need_cmd wmctrl; then _hxp_doctor_row wmctrl ok "window placement"
    else _hxp_doctor_row wmctrl opt "absent — no auto-tiling"; fi
    if _hxp_need_cmd xprop; then _hxp_doctor_row xprop ok "editor window id"
    else _hxp_doctor_row xprop opt "absent — editor id from \$WINDOWID only"; fi
    (( $+functions[_hxp_wm_kind] )) && _hxp_doctor_row wm-kind ok "$(_hxp_wm_kind)"
  fi

  print
  print -r -- "${C_H}Extras${C_R}"
  if _hxp_need_cmd gawk; then _hxp_doctor_row gawk ok "awk (mawk/busybox also work)"
  else _hxp_doctor_row gawk opt "POSIX awk — fine"; fi
  cjk="$(_hxp_cjk_font 2>/dev/null)"
  if [[ -n "$cjk" ]]; then _hxp_doctor_row cjk-font ok "$cjk"
  else _hxp_doctor_row cjk-font opt "none — set HXP_CJK_FONT for CJK markdown"; fi
}
