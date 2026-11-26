_hxp_need_cmd() { command -v "$1" >/dev/null 2>&1 }
_hxp_abs() { print -r -- "${1:A}" }

if ! zmodload -F zsh/files b:zf_mv b:zf_rm b:zf_mkdir 2>/dev/null; then
  zf_mv() { command mv "$@" }
  zf_rm() { command rm "$@" }
  zf_mkdir() { command mkdir "$@" }
fi
# zf_mv cannot cross filesystems.
_hxp_mv() { zf_mv -f -- "$1" "$2" 2>/dev/null || command mv -f -- "$1" "$2" }

_hxp_awk() {
  local REPLY
  _hxp_awk_reply
  print -r -- "$REPLY"
}

_hxp_awk_reply() {
  if [[ -n "$HXP_AWK" ]]; then REPLY="$HXP_AWK"
  elif _hxp_need_cmd gawk; then REPLY=gawk
  else REPLY=awk; fi
}

_hxp_gui_viewer() {
  local candidate
  for candidate in "${HXP_VIEWER:-}" zathura sioyek; do
    [[ "$candidate" == (zathura|sioyek) ]] || continue
    if _hxp_need_cmd "$candidate"; then print -r -- "$candidate"; return 0; fi
  done
  return 1
}

_hxp_split_check() {
  emulate -L zsh
  local why=""
  if [[ "${HXP_NO_SPLIT:-}" == 1 ]]; then why='disabled by HXP_NO_SPLIT=1'
  elif ! _hxp_need_cmd fancy-cat; then why='not installed'
  elif ! fancy-cat --help 2>&1 | grep -q -- '--listen'; then
    why='this build lacks --listen; install the fork'
  elif [[ -n "$TMUX" ]]; then
    if [[ -z "$TMUX_PANE" ]]; then why='tmux did not set TMUX_PANE'
    elif ! fancy-cat --tmux-supported >/dev/null 2>&1; then
      why='this tmux cannot pass graphics through'
    fi
  elif [[ "$TERM_PROGRAM" != ghostty ]]; then why='needs Ghostty or tmux'
  elif [[ "$WINDOWID" != <-> || -z "$DISPLAY" ]]; then
    why='Ghostty splits need X11 (WINDOWID and DISPLAY)'
  elif [[ -z "$GHOSTTY_SURFACE_ID" ]]; then why='Ghostty did not set GHOSTTY_SURFACE_ID'
  elif ! _hxp_need_cmd xdotool; then why='Ghostty splits need xdotool'
  fi
  [[ -z "$why" ]] && return 0
  print -r -- "$why"
  return 1
}

_hxp_fancy_cat_has_resolver() {
  fancy-cat --help 2>&1 | grep -q -- '--inverse-search-resolver'
}

_hxp_viewer() {
  if _hxp_split_check >/dev/null; then print -r -- fancy-cat; return 0; fi
  _hxp_gui_viewer
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
  # argv aliases zsh positional parameters.
  local -a cmd
  cmd=( "${(@f)$(_hxp_editor_argv "$@")}" )
  "${cmd[@]}"
}

# Match bash helpers: hash without a newline.
_hxp_state_file() {
  emulate -L zsh
  local key; key="$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)"
  print -r -- "${XDG_RUNTIME_DIR:-/tmp}/hxp/$key.state"
}

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
  if (( ${+HXP_CJK_FONT_RESOLVED} )); then
    [[ -n "$HXP_CJK_FONT_RESOLVED" ]] || return 1
    print -r -- "$HXP_CJK_FONT_RESOLVED"
    return 0
  fi
  _hxp_need_cmd fc-list || return 1

  local font families
  families=$'\n'"$(fc-list : family 2>/dev/null)"$'\n'
  for font in \
    'Noto Sans CJK KR' \
    'Noto Serif CJK KR' \
    'NanumGothic' \
    'NanumMyeongjo' \
    'Baekmuk Batang'
  do
    # Families include comma-separated aliases.
    if [[ "$families" == *[$'\n',]"$font"[$'\n',]* ]]; then
      print -r -- "$font"
      return 0
    fi
  done
  return 1
}

# CJK lead bytes: E3-ED (U+3000-U+DFFF).
_hxp_has_cjk() {
  emulate -L zsh
  local LC_ALL=C file
  for file in "$@"; do
    [[ -r "$file" && "$(<"$file")" == *[$'\xe3'-$'\xed']* ]] && return 0
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

_hxp_md_declared_keys() {
  emulate -L zsh
  local src="$1" awk_bin
  shift
  reply=()
  [[ -f "$src" && $# -gt 0 ]] || return 0
  _hxp_awk_reply; awk_bin="$REPLY"
  reply=( ${(f)"$("$awk_bin" -v keys="${(j: :)@}" '
    BEGIN { n = split(keys, want, " ") }
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    !fm || /^(---|\.\.\.)[[:space:]]*$/ { exit }
    {
      for (i = 1; i <= n; ++i)
        if (!(want[i] in seen) && $0 ~ "^[[:space:]]*" want[i] "[[:space:]]*:") {
          seen[want[i]] = 1
          print want[i]
        }
    }
  ' "$src" 2>/dev/null)"} )
}

_hxp_md_declares_key() {
  local -a reply
  _hxp_md_declared_keys "$1" "$2"
  (( ${#reply} ))
}

_hxp_watch_exts() {
  case "$1" in
    md)  print -r -- 'md,bib' ;;
    tex) print -r -- 'tex,bib,sty,cls' ;;
    typ) print -r -- 'typ,bib,yml,yaml' ;;
    *)   print -r -- "$1" ;;
  esac
}

_hxp_watch_match() {
  emulate -L zsh
  local ext="$1" path="$2" cbase="${2:t}"
  [[ "$cbase" == .* ]] && return 1
  [[ "$path" == *.hxp_build_*/* ]] && return 1
  local exts=",$(_hxp_watch_exts "$ext"),"
  [[ "$exts" == *",${cbase:e},"* ]]
}

_hxp_reload_viewer() {
  local viewer="${HXP_VIEWER_KIND:-}" socket="${HXP_VIEWER_SOCKET:-}" line
  # Native Typst starts before the preview exists; each watcher owns its route.
  if [[ -n "${HXP_VIEWER_ROUTE:-}" && -r "$HXP_VIEWER_ROUTE" ]]; then
    while IFS= read -r line; do
      case "$line" in
        viewer=*) viewer="${line#viewer=}" ;;
        viewer_socket=*) socket="${line#viewer_socket=}" ;;
      esac
    done < "$HXP_VIEWER_ROUTE"
  fi
  [[ "$viewer" == fancy-cat && -S "$socket" ]] || return 0
  # Polling is the fallback.
  fancy-cat --remote "$socket" reload >/dev/null 2>&1 || true
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
  local fallback="$1" file="$2" candidate root

  if [[ -z "$file" ]]; then
    print -r -- "$fallback"
    return
  fi

  if [[ "$file" != /* && -n "$fallback" ]]; then
    root="$(_hxp_root_for "$fallback" "${fallback:e}")"
    for candidate in "${root:h}/$file" "${fallback:h}/$file"; do
      if [[ -f "$candidate" ]]; then print -r -- "${candidate:A}"; return; fi
    done
  fi
  if [[ -f "$file" ]]; then print -r -- "${file:A}"; return; fi
  print -r -- "$file"
}

_hxp_runaway_hint() {
  emulate -L zsh
  local err_log="$1" awk_bin
  _hxp_awk_reply; awk_bin="$REPLY"

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
  local file="$1" hint="$2" needle awk_bin
  [[ -f "$file" && -n "$hint" ]] || return 0

  needle="$hint"
  [[ "$needle" == *". "* ]] && needle="${needle%%. *}."
  (( ${#needle} >= 8 )) || return 0

  # Use zsh character boundaries so awk versions agree.
  local -a chars=( "${(@s::)needle}" ) cuts=()
  local -i i bytes=0
  unsetopt multibyte
  for (( i = 1; i <= ${#chars}; ++i )); do
    (( bytes += ${#chars[i]} ))
    (( i >= 8 )) && cuts+=( "$bytes" )
  done
  _hxp_awk_reply; awk_bin="$REPLY"
  # ENVIRON preserves backslashes that -v would unescape.
  LC_ALL=C HXP_HINT_NEEDLE="$needle" HXP_HINT_CUTS="${(j: :)cuts}" "$awk_bin" '
    BEGIN {
      needle = ENVIRON["HXP_HINT_NEEDLE"]
      n = split(ENVIRON["HXP_HINT_CUTS"], cuts, " ")
    }
    {
      for (i = n; i > best; --i) {
        if (index($0, substr(needle, 1, cuts[i]))) {
          best = i; line = NR
          break
        }
      }
      if (best == n) exit
    }
    END { if (line) print line }
  ' < "$file" 2>/dev/null
}

_hxp_error_location() {
  emulate -L zsh
  local err_log="$1" fallback="$2" awk_bin loc file line col hint
  _hxp_awk_reply; awk_bin="$REPLY"

  loc="$("$awk_bin" -v fallback="$fallback" '
    /\.tex:[0-9]+:/ {
      if (match($0, /\.tex:[0-9]+:/)) {
        f = substr($0, 1, RSTART + 3)
        n = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", n)
        printf "%s\t%s\t\n", f, n
        done = 1; exit
      }
    }
    /:[0-9]+:[0-9]+[[:space:]]*$/ {
      s = $0; sub(/[[:space:]]+$/, "", s)
      c = s; sub(/^.*:/, "", c)
      sub(/:[0-9]+$/, "", s)
      l = s; sub(/^.*:/, "", l)
      sub(/:[0-9]+$/, "", s)
      f = s; sub(/^[[:space:]]*/, "", f)
      sub(/^(┌─|-->)[[:space:]]*/, "", f)
      printf "%s\t%s\t%s\n", f, l, c
      done = 1; exit
    }
    # l.NN belongs to the preceding <*> file.
    /^l\.[[:space:]]*[0-9]+/ {
      n = $0; sub(/^l\.[[:space:]]*/, "", n); sub(/[^0-9].*$/, "", n)
      printf "%s\t%s\t\n", (file == "" ? fallback : file), n
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

# FILE<TAB>LINE<TAB>COL; optional $3 is a cached location.
_hxp_error_pos_for() {
  emulate -L zsh
  local src="$1" err_log="$2" loc file line col

  loc="${3-$(_hxp_error_location "$err_log" "$src")}"
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

  IFS=$'\t' read -r file line col <<< "$(_hxp_error_pos_for "$src" "$err_log" "${@:4}")"
  cmd=( "${(@f)$(_hxp_editor_argv "$editor" "$file" "$line" "$col")}" )
  print -r -- "${cmd[*]}"
}

_hxp_error_extract() {
  emulate -L zsh
  local err_log="$1" awk_bin
  _hxp_awk_reply; awk_bin="$REPLY"

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

# Avoid double-counting LaTeX diagnostics.
_hxp_error_count() {
  emulate -L zsh
  local err_log="$1" awk_bin
  _hxp_awk_reply; awk_bin="$REPLY"

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
  _hxp_awk_reply; awk_bin="$REPLY"

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

_hxp_fold() {
  emulate -L zsh
  local width="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    while (( ${#line} > width )); do
      print -r -- "${line[1,width]}"
      line="${line[width+1,-1]}"
    done
    print -r -- "$line"
  done
}

_hxp_write_error_md() {
  emulate -L zsh
  local src="$1" ext="$2" err_log="$3" err_md="$4" debug_tex="$5" parts="${6:-}"
  local loc loc_file line col location extract primary source_line editor_cmd count count_label
  loc="$(_hxp_error_location "$err_log" "$src")"
  IFS=$'\t' read -r loc_file line col <<< "$loc"
  location="$loc_file"
  [[ -n "$line" ]] && location="${location}:${line}"
  [[ -n "$col" ]] && location="${location}:${col}"
  extract="$(_hxp_error_extract "$err_log")"
  primary="$(_hxp_primary_error "$err_log")"
  source_line="$(_hxp_source_line "$loc_file" "$line")"
  editor_cmd="$(_hxp_editor_target_for_error "$(_hxp_session_editor "$src")" "$src" "$err_log" "$loc")"
  count="$(_hxp_error_count "$err_log")"
  if [[ "$count" -gt 1 ]]; then
    count_label="Compile failed - $count errors"
  else
    count_label="Compile failed"
  fi

  local suspect="" nearby="" compiler latex_ctx="" mdline="" md_ctx=""
  [[ -n "$source_line" ]] && suspect="$line | $source_line"
  if [[ ( "$ext" == tex || "$ext" == typ ) && -n "$line" ]]; then
    nearby="$(_hxp_source_context "$loc_file" "$line")"
  fi
  compiler="$(if [[ -n "$extract" ]]; then print -r -- "$extract"; else tail -n 80 "$err_log"; fi | _hxp_fold 79)"
  if [[ "$ext" == md && -n "$line" && -f "$debug_tex" ]]; then
    local start=$(( line > 5 ? line - 5 : 1 ))
    latex_ctx="$(nl -ba "$debug_tex" | sed -n "${start},$(( line + 5 ))p")"
    mdline="$(_hxp_guess_md_line_from_tex "$src" "$debug_tex" "$line")"
    if [[ -n "$mdline" ]]; then
      start=$(( mdline > 5 ? mdline - 5 : 1 ))
      md_ctx="$(nl -ba "$src" | sed -n "${start},$(( mdline + 5 ))p")"
    fi
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
    print -r -- "\\colorbox{red!12}{\\parbox{\\dimexpr\\linewidth-2\\fboxsep}{\\Large\\bfseries $count_label}}"
    print -r -- '\endgroup'
    print
    print -r -- '# Look Here First'
    print
    [[ -n "$primary" ]] && print -rl -- "**Compiler says:** $primary" ''
    if [[ -n "$line" ]]; then
      print -r -- "**Location:** [\`$location\`](file://$loc_file#$line)"
    else
      print -r -- "**File:** [\`$loc_file\`](file://$loc_file)"
    fi
    print
    print -r -- "**Editor target:** \`$editor_cmd\`"
    print
    [[ -n "$suspect" ]] && print -rl -- '## Suspect Line' '```' "$suspect" '```' ''
    [[ -n "$nearby" ]] && print -rl -- '## Nearby Source' '```' "$nearby" '```' ''
    print -rl -- '## Compiler Extract' '```' "$compiler" '```'
    if [[ "$ext" == md ]]; then
      print -rl -- '' '## Where this really is' \
        'Pandoc PDF errors typically reference the generated LaTeX, not Markdown.'
      [[ -n "$line" ]] && print -r -- "- **LaTeX line:** [\`$debug_tex:$line\`](file://$debug_tex#$line)"
      [[ -n "$latex_ctx" ]] && print -rl -- '' '### LaTeX context (accurate)' '```' "$latex_ctx" '```'
      if [[ -n "$md_ctx" ]]; then
        print -rl -- '' '### Probable Markdown location (heuristic)' \
          "Best guess: around [\`$src:$mdline\`](file://$src#$mdline)" '```' "$md_ctx" '```'
      fi
    fi
  } >| "$err_md"

  [[ -n "$parts" && -d "$parts" ]] || return 0
  local name value file_only=""
  [[ -z "$line" ]] && file_only="$loc_file"
  for name value in \
      heading "$count_label" primary "$primary" location "${line:+$location}" \
      file "$file_only" link "file://$loc_file${line:+#$line}" \
      editor "$editor_cmd" suspect "$suspect" nearby "$nearby" compiler "$compiler" \
      latex-line "${line:+$debug_tex:$line}" latex-link "file://$debug_tex${line:+#$line}" \
      latex-context "$latex_ctx" md-guess "${mdline:+$src:$mdline}" md-context "$md_ctx"; do
    [[ -n "$value" ]] && print -r -- "$value" >| "$parts/$name.txt"
  done
  [[ "$ext" == md ]] && : >| "$parts/markdown.flag"
  return 0
}

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

  local -a reply fonts
  local REPLY=""
  _hxp_typst_font_args; fonts=( "${reply[@]}" )
  {
    print -r -- '#set page(margin: 0.75in)'
    _hxp_typst_font_rules "$REPLY"
    print -r -- "#block(width: 100%, inset: 10pt, radius: 4pt, fill: rgb(\"#fdecea\"), stroke: rgb(\"#dd3333\"))[#text(size: 15pt, weight: \"bold\", fill: rgb(\"#bb0000\"))[${heading}]]"
    print -r -- '#v(8pt)'
    printf '#raw(read("%s"), block: true)\n' "$base"
  } >| "$err_typ"

  typst compile --root "$root" "${fonts[@]}" "$err_typ" "$temp_pdf" >/dev/null 2>&1
  local rc=$?
  rm -f -- "$err_typ"
  return $rc
}

# Set reply to font arguments and REPLY to the CJK family.
_hxp_typst_font_args() {
  emulate -L zsh
  reply=( --ignore-system-fonts )
  REPLY=""
  local family file dir
  family="$(_hxp_cjk_font)" || return 0
  dir="${XDG_RUNTIME_DIR:-/tmp}/hxp/fonts/${family//[^A-Za-z0-9]/_}"
  if [[ ! -d "$dir" ]]; then
    zf_mkdir -p -m 700 -- "$dir" 2>/dev/null || return 0
    file="$(fc-match -f '%{file}' "$family" 2>/dev/null)"
    # Reject fc-match substitutions.
    if [[ -r "$file" && "$(fc-match -f '%{family}' "$family" 2>/dev/null)" == *"$family"* ]]; then
      ln -sf -- "$file" "$dir/font.${file:e:l}" 2>/dev/null
    fi
  fi
  [[ -O "$dir" ]] || return 0
  local -a found=( "$dir"/font.*(N-.) )
  (( ${#found} )) || return 0
  reply+=( --font-path "$dir" )
  REPLY="$family"
}

_hxp_typst_font_rules() {
  emulate -L zsh
  local family="${1//\\/\\\\}"
  family="${family//\"/\\\"}"
  if [[ -n "$family" ]]; then
    print -r -- "#set text(size: 10pt, font: (\"Libertinus Serif\", \"$family\"))"
    print -r -- "#show raw: set text(font: (\"DejaVu Sans Mono\", \"$family\"))"
  else
    print -r -- '#set text(size: 10pt)'
  fi
}

# Read report sections as text to avoid markup escaping.
_hxp_make_typst_report_pdf() {
  emulate -L zsh
  local parts="$1" temp_pdf="$2"
  _hxp_need_cmd typst && [[ -r "$parts/heading.txt" ]] || return 1
  local -a reply fonts
  local REPLY=""
  _hxp_typst_font_args; fonts=( "${reply[@]}" )
  {
    print -r -- '#let part(name) = read(name + ".txt").trim(at: end)'
    print -r -- '#set page(margin: 0.75in)'
    _hxp_typst_font_rules "$REPLY"
    print -r -- '#show raw.where(block: true): set text(size: 8.5pt)'
    print -r -- '#show link: set text(fill: blue)'
    print -r -- '#block(width: 100%, inset: 8pt, radius: 3pt, fill: rgb("#fdecea"), stroke: rgb("#dd3333"), text(size: 15pt, weight: "bold", fill: rgb("#bb0000"), part("heading")))'
    print -r -- '= Look Here First'
    [[ -s "$parts/primary.txt" ]] && print -r -- '*Compiler says:* #part("primary")' $'\n'
    if [[ -s "$parts/location.txt" ]]; then
      print -r -- '*Location:* #link(part("link"), raw(part("location")))' $'\n'
    else
      print -r -- '*File:* #link(part("link"), raw(part("file")))' $'\n'
    fi
    [[ -s "$parts/editor.txt" ]] && print -r -- '*Editor target:* #raw(part("editor"))'
    [[ -s "$parts/suspect.txt" ]] && print -r -- '== Suspect Line' $'\n' '#raw(part("suspect"), block: true)'
    [[ -s "$parts/nearby.txt" ]] && print -r -- '== Nearby Source' $'\n' '#raw(part("nearby"), block: true)'
    [[ -s "$parts/compiler.txt" ]] && print -r -- '== Compiler Extract' $'\n' '#raw(part("compiler"), block: true)'
    if [[ -e "$parts/markdown.flag" ]]; then
      print -r -- '== Where this really is' $'\n' 'Pandoc PDF errors typically reference the generated LaTeX, not Markdown.'
      [[ -s "$parts/latex-line.txt" ]] && print -r -- '- *LaTeX line:* #link(part("latex-link"), raw(part("latex-line")))'
      [[ -s "$parts/latex-context.txt" ]] && print -r -- '=== LaTeX context (accurate)' $'\n' '#raw(part("latex-context"), block: true)'
      if [[ -s "$parts/md-context.txt" ]]; then
        print -r -- '=== Probable Markdown location (heuristic)' $'\n' 'Best guess: around #raw(part("md-guess"))'
        print -r -- '#raw(part("md-context"), block: true)'
      fi
    fi
  } >| "$parts/report.typ"
  typst compile --root "$parts" "${fonts[@]}" "$parts/report.typ" "$temp_pdf" >/dev/null 2>&1
}

_hxp_error_pdf_marker() {
  emulate -L zsh
  if [[ -n "${HXP_ERRPDF_MARKER:-}" && "$1" == "${HXP_ERRPDF_PDF:-}" ]]; then
    REPLY="$HXP_ERRPDF_MARKER"
    return 0
  fi
  local state; state="$(_hxp_state_file "$1")"
  REPLY="${state:r}.errpdf"
}

_hxp_pdf_identity() { stat -c '%d:%i:%s:%y' -- "$1" 2>/dev/null }

_hxp_publish_error_pdf() {
  emulate -L zsh
  local temp_pdf="$1" pdf="$2" marker REPLY
  _hxp_mv "$temp_pdf" "$pdf" || return 1
  _hxp_error_pdf_marker "$pdf"; marker="$REPLY"
  zf_mkdir -p -- "${marker:h}" 2>/dev/null
  _hxp_pdf_identity "$pdf" >| "$marker" 2>/dev/null
  return 0
}

_hxp_is_error_pdf() {
  emulate -L zsh
  local marker id REPLY
  _hxp_error_pdf_marker "$1"; marker="$REPLY"
  id="$(_hxp_pdf_identity "$1")"
  [[ -n "$id" && -r "$marker" && "$(<"$marker")" == "$id" ]]
}

_hxp_forget_error_pdf() {
  local REPLY
  _hxp_error_pdf_marker "$1"
  zf_rm -f -- "$REPLY" 2>/dev/null
  return 0
}

_hxp_make_error_pdf() {
  emulate -L zsh
  local src="$1" ext="$2" err_log="$3" err_md="$4" temp_pdf="$5" debug_tex="$6"
  local pdf="$7" parts="" render=1
  local -a pdf_engine

  if [[ "${HXP_KEEP_LAST_GOOD:-}" == 1 && -s "$pdf" ]] && ! _hxp_is_error_pdf "$pdf"; then
    render=0
  fi
  # Keep report files outside the watched tree.
  if (( render )) && [[ "$ext" != typ ]] && _hxp_need_cmd typst; then
    local report_root="${XDG_RUNTIME_DIR:-/tmp}/hxp"
    if zf_mkdir -p -- "$report_root" 2>/dev/null; then
      parts="$(mktemp -d "$report_root/errdoc.XXXXXXXX")" || parts=""
    fi
  fi
  {
    _hxp_write_error_md "$src" "$ext" "$err_log" "$err_md" "$debug_tex" "$parts"
    (( render )) || return 1
    if [[ "$ext" == "typ" ]] && _hxp_make_typst_error_pdf "$err_log" "$temp_pdf"; then
      return 0
    fi
    if [[ -n "$parts" ]] && _hxp_make_typst_report_pdf "$parts" "$temp_pdf"; then
      return 0
    fi
  } always {
    [[ -n "$parts" ]] && zf_rm -rf -- "$parts" 2>/dev/null
  }

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

_hxp_sweep_artifacts() {
  emulate -L zsh
  local temp_pdf="$1" err_log="$2" err_md="$3" debug_tex="$4" synctex_gz="$5" build_dir="$6"
  rm -f -- "$temp_pdf" "${temp_pdf:r}.watch.pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" 2>/dev/null
  [[ -n "$build_dir" ]] && rm -rf -- "$build_dir" 2>/dev/null
  return 0
}

# Signal the first native result only after publication or error-report generation.
_hxp_typst_startup_result() {
  [[ -n "${HXP_STARTUP_RESULT:-}" && ! -e "$HXP_STARTUP_RESULT" ]] || return 0
  print -r -- "$1" >| "$HXP_STARTUP_RESULT.tmp" &&
    _hxp_mv "$HXP_STARTUP_RESULT.tmp" "$HXP_STARTUP_RESULT"
}

_hxp_typst_render_state() {
  emulate -L zsh
  local state="$1" buf="$2" src="$3" ext="$4" err_log="$5" err_md="$6" temp_pdf="$7" debug_tex="$8" pdf="$9"
  local watch_pdf="${10:-}"
  : >| "$err_log"
  if [[ "$state" == "ok" ]]; then
    if [[ -n "$watch_pdf" ]]; then
      [[ -s "$watch_pdf" ]] || return 1
      cp -f -- "$watch_pdf" "$temp_pdf" && _hxp_mv "$temp_pdf" "$pdf" || return 1
    fi
    _hxp_forget_error_pdf "$pdf"
    zf_rm -f -- "$err_md"
    _hxp_reload_viewer
    _hxp_typst_startup_result 0
    return 0
  fi
  print -rn -- "$buf" >> "$err_log"
  if _hxp_make_error_pdf "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf"; then
    if [[ -s "$temp_pdf" ]] && _hxp_publish_error_pdf "$temp_pdf" "$pdf"; then
      _hxp_reload_viewer
    fi
  fi
  zf_rm -f -- "$temp_pdf"
  _hxp_typst_startup_result 1
  return 0
}

# Errors flush after 100ms of silence.
_hxp_typst_watch_render() {
  emulate -L zsh
  local src="$1" ext="$2" err_log="$3" err_md="$4" temp_pdf="$5" debug_tex="$6" pdf="$7"
  local watch_pdf="${8:-}"

  if ! zmodload zsh/zselect 2>/dev/null; then
    cat >> "$err_log"
    return 0
  fi

  local line buf="" state="" to
  while true; do
    [[ -n "$state" ]] && to=10 || to=6000
    if zselect -t "$to" -r 0; then
      IFS= read -r line || break
      case "$line" in
        *"] compiling "*)            buf=""; state="" ;;
        *"compiled with errors"*)    state="fail" ;;
        *"compiled successfully"*|*"compiled with warning"*)
          _hxp_typst_render_state ok "$buf" \
            "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
          state=""; buf=""
          ;;
        watching\ *|"writing to "*|"") ;;
        *)                           buf+="$line"$'\n' ;;
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
  local -x PATH="/usr/bin:$PATH"  # Prefer system Pandoc for math support.
  local src="$1" ext="$2" dir="$3" stem="$4"
  local pdf="$5" temp_pdf="$6" err_log="$7" err_md="$8" debug_tex="$9" build_dir="${10}"

  zf_rm -f -- "$temp_pdf"
  : >| "$err_log"

  local ok=1
  local base="${src:t}"
  local -a reply

  local root_src; root_src="$(_hxp_root_for "$src" "$ext")"
  local root_dir="${root_src:h}"
  local root_base="${root_src:t}"
  local root_stem="${root_base:r}"
  local bib; bib="$(_hxp_bib_for "$root_src")"

  case "$ext" in
    md)
      local -a pdf_vars
      pdf_vars=( -V colorlinks=true -V linkcolor=blue -V urlcolor=blue )

      local -a declared
      _hxp_md_declared_keys "$src" bibliography CJKmainfont geometry
      declared=( "${reply[@]}" )

      local -a cite_args
      if (( ${declared[(Ie)bibliography]} )); then
        cite_args=( --citeproc )
      elif [[ -n "$bib" ]]; then
        cite_args=( --citeproc --bibliography="$bib" )
      fi

      local -a cjk_args
      if (( ! ${declared[(Ie)CJKmainfont]} )); then
        if [[ -n "$HXP_CJK_FONT" ]] || _hxp_has_cjk "$src" "$dir"/*.bib(N); then
          local cjk_font; cjk_font="$(_hxp_cjk_font)"
          [[ -n "$cjk_font" ]] && pdf_vars+=( -V "CJKmainfont=$cjk_font" )
        elif (( ${declared[(Ie)bibliography]} )); then
          local -x HXP_CJK_FONT_RESOLVED="$(_hxp_cjk_font)"
          [[ -n "$HXP_CJK_FONT_RESOLVED" ]] && cjk_args=(
            --lua-filter "${${(%):-%x}:A:h:h}/filters/cjk-bibliography.lua"
          )
        fi
      fi

      local md_margin="${HXP_MD_MARGIN-0.75in}"
      if [[ -n "$md_margin" ]] && (( ! ${declared[(Ie)geometry]} )); then
        [[ "$md_margin" == *=* ]] || md_margin="margin=$md_margin"
        pdf_vars+=( -V "geometry=$md_margin" )
      fi

      if _hxp_need_cmd latexmk; then
        # Retain TeX for SyncTeX; xelatex rejects dotfile outputs.
        zf_mkdir -p -- "$build_dir"
        local synctex_tex="$build_dir/${stem}.hxp.tex"
        if (
          cd -- "$dir" &&
          pandoc -f markdown+tex_math_single_backslash "${pdf_vars[@]}" "${cjk_args[@]}" "${cite_args[@]}" \
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

          # Keep paths unwrapped for error parsing.
          if (
            cd -- "$dir" &&
            max_print_line=10000 latexmk "${latexmk_engine[@]}" -synctex=1 \
                -interaction=nonstopmode -halt-on-error -file-line-error \
                -outdir="$build_dir" -auxdir="$build_dir" \
                "$synctex_tex" >>"$err_log" 2>&1
          ); then
            local build_stem="${${synctex_tex:t}:r}"
            if [[ -f "$build_dir/$build_stem.pdf" ]]; then
              _hxp_mv "$build_dir/$build_stem.pdf" "$temp_pdf"
              # Rename sidecars so searches never read partial writes.
              if [[ -f "$build_dir/$build_stem.synctex.gz" ]]; then
                local pdf_base="${${pdf:t}:r}"
                _hxp_mv "$build_dir/$build_stem.synctex.gz" "${pdf:h}/$pdf_base.synctex.gz" 2>/dev/null
              fi
              ok=0
            fi
          fi
        else
          debug_tex="$synctex_tex"
        fi
      else
        local -a pdf_engine
        if _hxp_need_cmd xelatex; then
          pdf_engine=( --pdf-engine=xelatex )
        elif _hxp_need_cmd lualatex; then
          pdf_engine=( --pdf-engine=lualatex )
        fi

        if (
          cd -- "$dir" &&
          pandoc -f markdown+tex_math_single_backslash "${pdf_engine[@]}" "${pdf_vars[@]}" "${cjk_args[@]}" "${cite_args[@]}" "$base" -o "$temp_pdf" \
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
      if (cd -- "$root_dir" && typst compile --root "$root_dir" "$root_src" "$temp_pdf") >"$err_log" 2>&1; then
        ok=0
      fi
      ;;

    tex)
      zf_mkdir -p -- "$build_dir"
      local -a bib_args
      [[ -n "$bib" ]] && bib_args=( -bibtex )
      if (
        cd -- "$root_dir" &&
        max_print_line=10000 latexmk -pdf -synctex=1 -interaction=nonstopmode -halt-on-error \
          -file-line-error \
          "${bib_args[@]}" \
          -outdir="$build_dir" -auxdir="$build_dir" \
          "$root_src" >"$err_log" 2>&1
      ); then
        if [[ -f "$build_dir/$root_stem.pdf" ]]; then
          _hxp_mv "$build_dir/$root_stem.pdf" "$temp_pdf"
          if [[ -f "$build_dir/$root_stem.synctex.gz" ]]; then
            _hxp_mv "$build_dir/$root_stem.synctex.gz" "${pdf:h}/$root_stem.synctex.gz" 2>/dev/null
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
    _hxp_mv "$temp_pdf" "$pdf"
    _hxp_forget_error_pdf "$pdf"
    zf_rm -f -- "$err_md"
    [[ "$ext" != "md" ]] && zf_rm -f -- "$debug_tex"
    _hxp_reload_viewer
    return 0
  fi

  if _hxp_make_error_pdf "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf"; then
    if [[ -s "$temp_pdf" ]] && _hxp_publish_error_pdf "$temp_pdf" "$pdf"; then
      _hxp_reload_viewer
    fi
  fi
  zf_rm -f -- "$temp_pdf"
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

  # Pandoc may report deleted TeX files.
  if [[ -n "$line" && -f "$file" ]]; then
    printf '  %sat%s %s:%s%s\n' "$C_DIM" "$C_RST" "$file" "$line" "${col:+:$col}"
    local source_line; source_line="$(_hxp_source_line "$file" "$line")"
    [[ -n "$source_line" ]] && printf '\n  %s|%s %s\n' "$C_DIM" "$C_RST" "$source_line"
  fi

  local cmd
  cmd="$(_hxp_editor_target_for_error "$(_hxp_session_editor "$src")" "$src" "$err_log" "$loc")"
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

  # Deleting err_md signals recovery.
  local changed _drain
  inotifywait -m -q -e close_write -e moved_to -e create -e delete \
      --format '%w%f' "$dir" 2>/dev/null \
    | while IFS= read -r changed; do
        case "$changed" in
          "$err_log"|"$err_md"|"$pdf") ;;
          *) continue ;;
        esac
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
  if [[ -n "$viewer" ]]; then _hxp_doctor_row "$viewer" ok "active viewer"
  else _hxp_doctor_row viewer miss "no usable fancy-cat split, Zathura, or Sioyek"; fi
  if [[ "$viewer" != fancy-cat ]]; then
    _hxp_doctor_row fancy-cat opt "split unavailable: $(_hxp_split_check)"
  fi

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
  if [[ "$viewer" == fancy-cat ]]; then
    if ! _hxp_fancy_cat_has_resolver; then
      _hxp_doctor_row fancy-cat opt "build lacks --inverse-search-resolver — update the fork for PDF Ctrl+L and Typst lookup"
    elif _hxp_need_cmd hxp-inverse && _hxp_need_cmd python3; then
      _hxp_doctor_row hxp-inverse ok "Ctrl+L: SyncTeX or Typst prose lookup"
    else
      _hxp_doctor_row hxp-inverse miss "needs python3 and hxp-inverse — rerun install.sh"
    fi
    if [[ -n "$TMUX" ]] && _hxp_need_cmd tmux; then
      local mouse_binding; mouse_binding="$(tmux list-keys -T root C-MouseDown1Pane 2>/dev/null)"
      if [[ "$mouse_binding" != *'send-keys -M'* ]]; then
        _hxp_doctor_row Ctrl+click opt "tmux intercepts it — use Ctrl+L or add the manual's mouse binding"
      fi
    fi
  fi
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
