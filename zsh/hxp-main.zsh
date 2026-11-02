# hxp / wpdf entrypoints; source from .zshrc.

[[ -r "$HOME/.zsh/hxp-lib.zsh" ]] && source "$HOME/.zsh/hxp-lib.zsh"

_hxp_active_window_id() {
  emulate -L zsh
  command -v xprop >/dev/null 2>&1 || return 1

  local line wid
  line="$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null)" || return 1
  wid="${line##* }"
  [[ "$wid" == 0x* && "$wid" != "0x0" ]] || return 1
  print -r -- "$wid"
}

_hxp_editor_window_id() {
  emulate -L zsh

  if [[ -n "$WINDOWID" && "$WINDOWID" == <-> ]]; then
    print -r -- "$WINDOWID"
    return 0
  fi

  _hxp_active_window_id
}

_hxp_wm_kind() {
  emulate -L zsh
  if [[ "$HXP_WM" == "tiling" || "$HXP_WM" == "floating" ]]; then
    print -r -- "$HXP_WM"
    return 0
  fi

  local wm=""
  if command -v wmctrl >/dev/null 2>&1; then
    wm="$(wmctrl -m 2>/dev/null | awk -F': *' 'tolower($1)=="name"{print tolower($2); exit}')"
  fi
  if [[ -z "$wm" ]] && command -v xprop >/dev/null 2>&1; then
    wm="$(xprop -root -notype _NET_WM_NAME 2>/dev/null | awk -F\" '{print tolower($2); exit}')"
  fi

  case "$wm" in
    *i3*|*sway*|*bspwm*|*dwm*|*awesome*|*xmonad*|*qtile*|*herbstluft*|*river*|*hyprland*)
      print -r -- tiling ;;
    *)
      print -r -- floating ;;
  esac
}

_hxp_wmctrl_workarea() {
  emulate -L zsh
  command -v wmctrl >/dev/null 2>&1 || return 1

  wmctrl -d 2>/dev/null | awk '
    $2 == "*" {
      for (i = 1; i <= NF; i++) {
        if ($i == "WA:") {
          split($(i + 1), p, ",")
          split($(i + 2), s, "x")
          print p[1], p[2], s[1], s[2]
          exit
        }
      }
    }
  '
}

_hxp_wmctrl_tile() {
  emulate -L zsh
  [[ "$HXP_NO_TILE" == "1" ]] && return 0
  # Let tiling WMs place managed windows.
  [[ "$(_hxp_wm_kind)" == "tiling" ]] && return 0
  command -v wmctrl >/dev/null 2>&1 || return 1

  local ref="$1" side="$2" mode="${3:-name}"
  local -a wa ref_args
  wa=( $(_hxp_wmctrl_workarea) )
  (( ${#wa[@]} == 4 )) || return 1

  local x="${wa[1]}" y="${wa[2]}" width="${wa[3]}" height="${wa[4]}"
  (( width > 0 && height > 0 )) || return 1

  local half=$(( width / 2 ))
  local win_x="$x" win_w="$half"
  if [[ "$side" == "right" ]]; then
    win_x=$(( x + half ))
    win_w=$(( width - half ))
  fi

  if [[ "$mode" == "id" ]]; then
    ref_args=( -i -r "$ref" )
  else
    ref_args=( -r "$ref" )
  fi

  wmctrl "${ref_args[@]}" -b remove,maximized_vert,maximized_horz 2>/dev/null
  sleep 0.05
  wmctrl "${ref_args[@]}" -e "0,$win_x,$y,$win_w,$height" >/dev/null 2>&1
}

_hxp_find_viewer_window() {
  emulate -L zsh
  command -v wmctrl >/dev/null 2>&1 || return 1

  local viewer="${1:l}" pid="$2" pdf="$3" before="$4"
  local base="${${pdf:t}:l}"
  local id

  # Claim only new, unambiguous windows; Sioyek shares its process.
  id="$(wmctrl -lpx 2>/dev/null | awk -v viewer="$viewer" -v pid="$pid" \
      -v base="$base" -v before="$before" '
    BEGIN {
      n=split(before, ids, "\n")
      for (i=1; i<=n; i++) old[tolower(ids[i])]=1
    }
    {
      if (old[tolower($1)] || index(tolower($4), viewer) == 0) next
      # Identify Zathura by PID; window titles are configurable.
      if (viewer == "zathura") {
        if ($3 == pid) { pid_count++; pid_id=$1 }
        next
      }
      title=""
      for (i=6; i<=NF; i++) title=title " " $i
      if (index(tolower(title), base) == 0) next
      count++; id=$1
      if ($3 == pid) { pid_count++; pid_id=$1 }
    }
    END {
      if (pid_count == 1) print pid_id
      else if (count == 1) print id
    }
  ')"
  [[ -n "$id" ]] || return 1
  print -r -- "$id"
}

_hxp_wait_for_viewer_window() {
  emulate -L zsh
  command -v wmctrl >/dev/null 2>&1 || return 1

  # Track ownership even when tiling is disabled.
  local viewer="$1" pid="$2" pdf="$3" before="$4" id i
  for i in {1..40}; do
    id="$(_hxp_find_viewer_window "$viewer" "$pid" "$pdf" "$before")"
    if [[ -n "$id" ]]; then
      print -r -- "$id"
      return 0
    fi
    sleep 0.05
  done
  return 1
}

_hxp_close_viewer() {
  emulate -L zsh
  local viewer="$1" pid="$2" wid="$3"
  if [[ -n "$wid" ]] && command -v wmctrl >/dev/null 2>&1; then
    wmctrl -ic "$wid" 2>/dev/null && return 0
  fi
  # Never kill the shared Sioyek process.
  if [[ "$viewer" != "sioyek" && -n "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null
  fi
  return 0
}

wpdf() {
  emulate -L zsh
  setopt pipefail

  local quiet=0 no_initial=0
  while [[ "$1" == -* ]]; do
    case "$1" in
      -q|--quiet)   quiet=1; shift ;;
      --no-initial) no_initial=1; shift ;;   # caller (hxp) already did it
      --) shift; break ;;
      *) break ;;
    esac
  done

  local src="$1"
  [[ -z "$src" ]] && { print -u2 -- "usage: wpdf [-q] [--no-initial] <file.{md,tex,typ}>"; return 2; }
  [[ ! -f "$src" ]] && { print -u2 -- "wpdf: not found: $src"; return 2; }

  _hxp_need_cmd inotifywait || { print -u2 -- "wpdf: missing inotifywait (install inotify-tools)"; return 2; }
  _hxp_need_cmd pandoc     || { print -u2 -- "wpdf: missing pandoc"; return 2; }

  src="$(_hxp_abs "$src")"
  local dir="${src:h}"
  local base="${src:t}"
  local stem="${base:r}"
  local ext="${base:e}"

  local pdf; pdf="$(_hxp_pdf_for "$src" "$ext")"
  local temp_pdf="$dir/.${stem}.tmp.pdf"
  local err_log="$dir/.${stem}.error.log"
  local err_md="$dir/.${stem}.error.md"
  local debug_tex="$dir/.${stem}.debug.tex"
  local build_dir="$dir/.hxp_build_${stem}"
  local synctex_gz="${pdf:r}.synctex.gz"

  case "$ext" in
    md) ;;
    typ) _hxp_need_cmd typst   || { print -u2 -- "wpdf: missing typst"; return 2; } ;;
    tex) _hxp_need_cmd latexmk || { print -u2 -- "wpdf: missing latexmk"; return 2; } ;;
    *)   print -u2 -- "wpdf: unsupported extension: $ext"; return 2 ;;
  esac

  # Return on interruption so foreground wpdf leaves the shell alive.
  trap '_hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"; return 0' INT TERM HUP

  if (( no_initial == 0 )); then
    _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null
  fi

  (( quiet == 0 )) && print -- "wpdf: watching $src -> $pdf"

  if [[ "$ext" == "typ" && "$HXP_NO_NATIVE_TYP" != "1" ]] && zmodload zsh/zselect 2>/dev/null; then
    local root_src; root_src="$(_hxp_root_for "$src" typ)"
    local root_dir="${root_src:h}"

    # Publish snapshots atomically; retain watch output for error recovery.
    local watch_pdf="${temp_pdf:r}.watch.pdf"
    typst watch --root "$root_dir" "$root_src" "$watch_pdf" 2>&1 \
      | _hxp_typst_watch_render "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
    _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
    return
  fi

  # Watch the root directory so included sources also trigger builds.
  local root_src; root_src="$(_hxp_root_for "$src" "$ext")"
  local watch_dir="${root_src:h}"
  local watch_exts; watch_exts="$(_hxp_watch_exts "$ext")"
  local -a inotify_recurse=()
  [[ "$ext" == "tex" || "$ext" == "typ" ]] && inotify_recurse=( -r )

  if _hxp_need_cmd watchexec && [[ "$HXP_NO_WATCHEXEC" != "1" ]]; then
    (( quiet == 0 )) && print -- "wpdf: watchexec mode"
    # Keep the shell for cleanup; ignore generated sources to prevent loops.
    watchexec \
      --debounce 250ms \
      --postpone \
      --no-process-group \
      --no-vcs-ignore \
      --quiet \
      -w "$watch_dir" \
      -e "$watch_exts" \
      --ignore "**/.*" \
      --ignore "**/.hxp_build_*/**" \
      -- hxp-compile "$src" "$ext" "$dir" "$stem" \
                    "$pdf" "$temp_pdf" "$err_log" "$err_md" \
                    "$debug_tex" "$build_dir"
    _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
    return
  fi

  # Fallback: filter project events and debounce for 200ms.
  local changed _drain
  while IFS= read -r changed; do
    _hxp_watch_match "$ext" "$changed" || continue
    while IFS= read -r -t 0.2 _drain 2>/dev/null; do :; done

    [[ -f "$src" ]] || { (( quiet == 0 )) && print -- "wpdf: source vanished, exiting"; break; }

    if _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null; then
      (( quiet == 0 )) && print -- "wpdf: OK  $(date +%H:%M:%S)"
    else
      (( quiet == 0 )) && print -- "wpdf: ERR $(date +%H:%M:%S)  (see $err_log)"
    fi
  done < <(
    inotifywait -m -q "${inotify_recurse[@]}" \
      -e close_write -e moved_to \
      --format '%w%f' "$watch_dir"
  )

  _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
}


hxp() {
  emulate -L zsh
  setopt pipefail
  unsetopt monitor

  # Export for child processes; session state overrides inherited settings.
  local -x HXP_EDITOR="${HXP_EDITOR:-}"

  while [[ "$1" == -* ]]; do
    case "$1" in
      --doctor)  _hxp_doctor; return 0 ;;
      --micro)   HXP_EDITOR=micro; shift ;;
      --helix)   HXP_EDITOR=helix; shift ;;
      --)        shift; break ;;
      *)         print -u2 "hxp: unknown option: $1"; return 2 ;;
    esac
  done

  if [[ "$1" == "doctor" ]]; then
    _hxp_doctor
    return 0
  fi

  local editor editor_bin
  editor="$(_hxp_editor)"
  editor_bin="$(_hxp_editor_bin "$editor")"
  _hxp_need_cmd "$editor_bin" || { print -u2 "hxp: missing editor: $editor_bin"; return 2; }

  local src="$1"
  [[ -z "$src" ]] && { print -u2 "usage: hxp [--micro|--helix] <file.{md,tex,typ}>  |  hxp --doctor"; return 2; }

  if [[ ! -f "$src" ]]; then
    case "${${src:t}:e}" in
      md|tex|typ)
        _hxp_scaffold "$src" || { print -u2 "hxp: cannot create $src"; return 2; }
        print -- "hxp: created $src with starter scaffold"
        ;;
      *) print -u2 "hxp: not found: $src (and unknown extension — won't scaffold)"; return 2 ;;
    esac
  fi

  src="$(_hxp_abs "$src")"
  local dir="${src:h}"
  local base="${src:t}"
  local stem="${base:r}"
  local ext="${base:e}"

  local pdf; pdf="$(_hxp_pdf_for "$src" "$ext")"
  local temp_pdf="$dir/.${stem}.tmp.pdf"
  local err_log="$dir/.${stem}.error.log"
  local err_md="$dir/.${stem}.error.md"
  local debug_tex="$dir/.${stem}.debug.tex"
  local build_dir="$dir/.hxp_build_${stem}"
  local synctex_tex="$build_dir/${stem}.hxp.tex"
  local synctex_gz="${pdf:r}.synctex.gz"

  # Capture the editor window before focus changes.
  local editor_wid; editor_wid="$(_hxp_editor_window_id)"

  local viewer; viewer="$(_hxp_viewer)"

  # Search helpers use this session state to find the editor and viewer.
  local state_file; state_file="$(_hxp_state_file "$src")"
  mkdir -p -- "${state_file:h}" 2>/dev/null
  {
    print -r -- "src=$src"
    print -r -- "pdf=$pdf"
    print -r -- "viewer=$viewer"
    print -r -- "editor=$editor"
    print -r -- "tmux=$TMUX"
    print -r -- "tmux_pane=$TMUX_PANE"
    print -r -- "windowid=$editor_wid"
    print -r -- "pid=$$"
  } >| "$state_file" 2>/dev/null

  local initial_ok=0
  if _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" \
      "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null; then
    initial_ok=1
  fi

  if [[ -n "$editor_wid" ]]; then
    _hxp_wmctrl_tile "$editor_wid" left id
  else
    _hxp_wmctrl_tile :ACTIVE: left
  fi

  local before_windows="" viewer_wid="" zpid="" track_window=0 launch_lockfd=""
  local launch_lock="${state_file:h}/viewer-launch.lock"
  if command -v wmctrl >/dev/null 2>&1 && wmctrl -l >/dev/null 2>&1; then
    # Serialize launches so sessions cannot claim each other's windows.
    if zmodload zsh/system 2>/dev/null &&
        : >> "$launch_lock" &&
        zsystem flock -t 10 -i 0.05 -f launch_lockfd "$launch_lock"; then
      track_window=1
    else
      print -u2 -- 'hxp: could not lock viewer startup; retry the session'
      _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
      rm -f -- "$state_file"
      return 2
    fi
  fi

  {
    if (( track_window )); then
      before_windows="$(wmctrl -l 2>/dev/null | awk '{print $1}')" || track_window=0
    fi
    case "$viewer" in
      sioyek)
        sioyek --new-window "$pdf" >/dev/null 2>&1 &!
        zpid=$!
        { sleep 0.5 && sioyek --execute-command toggle_synctex --nofocus; } >/dev/null 2>&1 &!
        ;;
      zathura|*) zathura "$pdf" >/dev/null 2>&1 &!; zpid=$! ;;
    esac
    if (( track_window )); then
      viewer_wid="$(_hxp_wait_for_viewer_window "$viewer" "$zpid" "$pdf" "$before_windows")"
    fi
  } always {
    [[ -n "$launch_lockfd" ]] && zsystem flock -u "$launch_lockfd"
  }
  # Pin searches to our process when another viewer has the same PDF open.
  print -r -- "viewer_pid=$zpid" >> "$state_file" 2>/dev/null
  print -r -- "viewer_windowid=$viewer_wid" >> "$state_file" 2>/dev/null
  [[ -n "$viewer_wid" ]] && _hxp_wmctrl_tile "$viewer_wid" right id

  HXP_VIEWER_PID=$zpid HXP_VIEWER_KIND=$viewer wpdf -q --no-initial "$src" >/dev/null 2>&1 &!
  local wpid=$!


  cleanup() {
    [[ -n "$wpid" ]] && { pkill -TERM -P "$wpid" 2>/dev/null; kill -TERM "$wpid" 2>/dev/null; }

    _hxp_close_viewer "$viewer" "$zpid" "$viewer_wid"

    # Remove scratch files; keep the rendered PDF.
    rm -f -- "$temp_pdf" "${temp_pdf:r}.watch.pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_tex" "$synctex_gz" 2>/dev/null
    rm -rf -- "$build_dir" 2>/dev/null
    [[ -n "$state_file" ]] && rm -f -- "$state_file" "$state_file.buf" 2>/dev/null
  }

  trap 'cleanup; return 130' INT
  trap 'cleanup; return 143' TERM HUP

  if [[ -n "$editor_wid" && "$HXP_NO_TILE" != "1" ]] && command -v wmctrl >/dev/null 2>&1; then
    wmctrl -ia "$editor_wid" >/dev/null 2>&1
  fi

  if (( initial_ok == 0 )); then
    local _dtex=""
    [[ -f "$synctex_tex" ]] && _dtex="$synctex_tex"
    [[ -z "$_dtex" && -f "$debug_tex" ]] && _dtex="$debug_tex"
    if [[ "$ext" == "md" && -n "$_dtex" ]]; then
      _hxp_editor_open "$editor" "$src" "" "" "$err_log" "$_dtex"
    else
      local _ef _el _ec
      IFS=$'\t' read -r _ef _el _ec <<< "$(_hxp_error_pos_for "$src" "$err_log")"
      _hxp_editor_open "$editor" "$_ef" "$_el" "$_ec" "$err_log"
    fi
  else
    _hxp_editor_open "$editor" "$src" "" ""
  fi

  cleanup
  trap - INT TERM HUP
}
