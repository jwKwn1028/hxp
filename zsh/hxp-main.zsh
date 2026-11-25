[[ -r "$HOME/.zsh/hxp-lib.zsh" ]] && source "$HOME/.zsh/hxp-lib.zsh"

_hxp_claim_split() {
  emulate -L zsh
  [[ -o interactive && -z "$TMUX" && "$TERM_PROGRAM" == ghostty &&
     "$WINDOWID" == <-> && -n "$GHOSTTY_SURFACE_ID" ]] || return 0
  local root="${XDG_RUNTIME_DIR:-/tmp}/hxp-preview-$UID"
  [[ -L "$root/window-$WINDOWID" && -O "$root" && ! -L "$root" &&
     "$(stat -c %a -- "$root")" == 700 ]] || return 0
  local session
  session="$(readlink -- "$root/window-$WINDOWID" 2>/dev/null)" || return 0
  [[ "${session:h}" == "$root" && -O "$session" && -r "$session/source-surface" ]] || return 0
  [[ "$(<"$session/source-surface")" != "$GHOSTTY_SURFACE_ID" ]] || return 0
  local owner="$(<"$session/owner")"
  [[ "$owner" == <-> ]] && kill -0 "$owner" 2>/dev/null || return 0
  ln -- "$session/owner" "$session/claimed" 2>/dev/null || return 0
  local pdf="$(<"$session/pdf")" src=""
  [[ -r "$session/src" ]] && src="$(<"$session/src")"
  local -a viewer_args=(--listen "$session/socket" --inverse-search hxp-jump)
  [[ -e "$session/resolver" ]] && viewer_args+=(--inverse-search-resolver hxp-inverse)
  # Exit normally to close the Ghostty split.
  (
    zmodload zsh/system
    print -r -- "$sysparams[pid]" > "$session/pid"
    # Ghostty shells need an explicit session pin.
    [[ "$src" == /* ]] && export HXP_PREVIEW_SRC="$src"
    exec fancy-cat "${viewer_args[@]}" "$pdf"
  )
  exit 0
}
_hxp_claim_split

# Detect PID reuse.
_hxp_proc_start() {
  emulate -L zsh
  [[ "$1" == <-> && -r "/proc/$1/stat" ]] || return 1
  local stat; stat="$(<"/proc/$1/stat")" || return 1
  stat="${stat##*) }"                   # fields after "pid (comm) "
  print -r -- "${${(s: :)stat}[20]}"
}

_hxp_ghostty_pid() {
  emulate -L zsh
  local pid=$$ stat
  while (( pid > 1 )) && [[ -r "/proc/$pid/stat" ]]; do
    if [[ "$(<"/proc/$pid/comm")" == ghostty ]]; then print -r -- "$pid"; return 0; fi
    stat="$(<"/proc/$pid/stat")"
    stat="${stat##*) }"
    pid="${${(s: :)stat}[2]}"
  done
  return 1
}

_hxp_new_split_shell() {
  emulate -L zsh
  local term_pid="$1" before="$2" child env found=""
  for child in ${(f)"$(pgrep -P "$term_pid" 2>/dev/null)"}; do
    [[ " $before " == *" $child "* ]] && continue
    env=$'\n'"$(tr '\0' '\n' < "/proc/$child/environ" 2>/dev/null)"$'\n'
    [[ "$env" == *$'\nWINDOWID='"$WINDOWID"$'\n'* ]] || continue
    [[ "$env" == *$'\nGHOSTTY_SURFACE_ID='"$GHOSTTY_SURFACE_ID"$'\n'* ]] && continue
    [[ -z "$found" ]] || return 1        # ambiguous
    found="$child"
  done
  [[ -n "$found" ]] || return 1
  local start; start="$(_hxp_proc_start "$found")" || return 1
  print -r -- "$found:$start"
}

_hxp_release_split() {
  emulate -L zsh
  [[ -n "$preview_dir" ]] || return 0
  if [[ -n "$preview_pane" ]]; then
    tmux kill-pane -t "$preview_pane" 2>/dev/null
  else
    local pid="" shell_pid="${preview_shell%%:*}"
    [[ -r "$preview_dir/pid" ]] && pid="$(<"$preview_dir/pid")"
    if [[ "$pid" == <-> && -r "/proc/$pid/cmdline" ]] &&
       grep -Fzxq -- "$preview_dir/socket" "/proc/$pid/cmdline"; then
      kill -TERM "$pid" 2>/dev/null
    elif [[ -n "$shell_pid" && "$(_hxp_proc_start "$shell_pid")" == "${preview_shell#*:}" ]]; then
      pkill -HUP -P "$shell_pid" 2>/dev/null
      kill -HUP "$shell_pid" 2>/dev/null
    fi
  fi
  rm -rf -- "$preview_dir"
  preview_dir=''; preview_pane=''; preview_shell=''
}

_hxp_start_split() {
  emulate -L zsh
  local root="${XDG_RUNTIME_DIR:-/tmp}/hxp-preview-$UID"
  mkdir -m 700 -- "$root" 2>/dev/null || [[ -d "$root" ]] || return 1
  [[ -O "$root" && ! -L "$root" && "$(stat -c %a -- "$root")" == 700 ]] || return 1
  preview_dir="$(mktemp -d "$root/session.XXXXXXXX")" || return 1
  local win_request="" lockfd="" term_pid="" before_shells="" i resolver=0
  local -a viewer_args=(--listen "$preview_dir/socket" --inverse-search hxp-jump)
  if _hxp_fancy_cat_has_resolver; then
    resolver=1
    viewer_args+=(--inverse-search-resolver hxp-inverse)
  fi
  {
    if [[ -n "$TMUX" ]]; then
      # Override the tmux server environment with this session pin.
      preview_pane="$(tmux split-window -hdP -F '#{pane_id}' -t "$TMUX_PANE" -c "$PWD" \
        -e "HXP_PREVIEW_SRC=$HXP_SESSION_SRC" fancy-cat "${viewer_args[@]}" "$pdf")" || return 1
    else
      [[ "$(xdotool getactivewindow)" == "$WINDOWID" ]] || return 1
      print -r -- "$GHOSTTY_SURFACE_ID" > "$preview_dir/source-surface"
      print -r -- "$pdf" > "$preview_dir/pdf"
      print -r -- "$HXP_SESSION_SRC" > "$preview_dir/src"
      (( resolver )) && : > "$preview_dir/resolver"
      print -r -- "$$" > "$preview_dir/owner"
      zmodload zsh/system || return 1
      : >> "$root/window-$WINDOWID.lock" || return 1
      zsystem flock -t 0 -f lockfd "$root/window-$WINDOWID.lock" || return 1
      ln -sfT -- "$preview_dir" "$root/window-$WINDOWID" || return 1
      win_request="$root/window-$WINDOWID"
      term_pid="$(_hxp_ghostty_pid)" && before_shells="$(pgrep -P "$term_pid" | tr '\n' ' ')"
      xdotool key --clearmodifiers ctrl+shift+o || return 1
    fi
    for i in {1..160}; do
      [[ -S "$preview_dir/socket" ]] && break
      if [[ -n "$term_pid" && -z "$preview_shell" ]]; then
        preview_shell="$(_hxp_new_split_shell "$term_pid" "$before_shells")"
      fi
      sleep 0.05
    done
    [[ -S "$preview_dir/socket" ]] || return 1
    if [[ -n "$win_request" && "$(xdotool getactivewindow)" == "$WINDOWID" ]]; then
      xdotool key --clearmodifiers ctrl+shift+h
    fi
    return 0
  } always {
    [[ -n "$win_request" ]] && rm -f -- "$win_request"
    [[ -n "$lockfd" ]] && zsystem flock -u "$lockfd"
  }
}

# Stop HUP-ignoring editors after tty loss.
_hxp_hangup_watchdog() {
  emulate -L zsh
  trap '' HUP INT
  trap - TERM
  local shell_pid="$1" stat child children
  local -a names=( "${@:2}" ) fields editors alive
  zmodload zsh/zselect 2>/dev/null || return 1
  _hxp_tty_nr() {
    [[ -r "/proc/$shell_pid/stat" ]] || return 1
    stat="$(<"/proc/$shell_pid/stat")"
    fields=( ${(s: :)${stat##*) }} )  # state ppid pgrp session tty_nr ...
  }
  _hxp_tty_nr && (( fields[5] != 0 )) || return 1   # no tty
  while :; do
    zselect -t 100
    _hxp_tty_nr || return 1
    (( fields[5] == 0 )) && break
  done
  children="$(<"/proc/$shell_pid/task/$shell_pid/children")" 2>/dev/null
  for child in ${=children}; do
    [[ -r "/proc/$child/comm" ]] && (( ${names[(Ie)$(<"/proc/$child/comm")]} )) && editors+=( "$child" )
  done
  (( ${#editors} )) || return 0
  kill -TERM "${editors[@]}" 2>/dev/null
  repeat 20; do
    zselect -t 10
    alive=()
    for child in "${editors[@]}"; do [[ -e "/proc/$child" ]] && alive+=( "$child" ); done
    editors=( "${alive[@]}" )
    (( ${#editors} )) || return 0
  done
  kill -KILL "${editors[@]}" 2>/dev/null
}

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

  # Claim only new, unambiguous windows.
  id="$(wmctrl -lpx 2>/dev/null | awk -v viewer="$viewer" -v pid="$pid" \
      -v base="$base" -v before="$before" '
    BEGIN {
      n=split(before, ids, "\n")
      for (i=1; i<=n; i++) old[tolower(ids[i])]=1
    }
    {
      if (old[tolower($1)] || index(tolower($4), viewer) == 0) next
      # Zathura titles are configurable; match its PID.
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
  # Sioyek may share its process.
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
      --keep-last-good) local -x HXP_KEEP_LAST_GOOD=1; shift ;;
      -q|--quiet)   quiet=1; shift ;;
      --no-initial) no_initial=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  local src="$1"
  [[ -z "$src" ]] && { print -u2 -- "usage: wpdf [-q] [--no-initial] [--keep-last-good] <file.{md,tex,typ}>"; return 2; }
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

  local -x HXP_ERRPDF_PDF="$pdf" HXP_ERRPDF_MARKER
  local -x HXP_CJK_FONT_RESOLVED="${HXP_CJK_FONT_RESOLVED-$(_hxp_cjk_font)}"
  HXP_ERRPDF_MARKER="${$(_hxp_state_file "$pdf"):r}.errpdf"

  # Interrupt wpdf without exiting the shell.
  trap '_hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"; return 0' INT TERM HUP

  if (( no_initial == 0 )); then
    _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null
  fi

  (( quiet == 0 )) && print -- "wpdf: watching $src -> $pdf"

  if [[ "$ext" == "typ" && "$HXP_NO_NATIVE_TYP" != "1" ]] && zmodload zsh/zselect 2>/dev/null; then
    local root_src; root_src="$(_hxp_root_for "$src" typ)"
    local root_dir="${root_src:h}"

    local watch_pdf="${temp_pdf:r}.watch.pdf"
    (cd -- "$root_dir" && typst watch --root "$root_dir" "$root_src" "$watch_pdf") 2>&1 \
      | _hxp_typst_watch_render "$src" "$ext" "$err_log" "$err_md" "$temp_pdf" "$debug_tex" "$pdf" "$watch_pdf"
    _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
    return
  fi

  local root_src; root_src="$(_hxp_root_for "$src" "$ext")"
  local watch_dir="${root_src:h}"
  local watch_exts; watch_exts="$(_hxp_watch_exts "$ext")"
  local -a inotify_recurse=()
  [[ "$ext" == "tex" || "$ext" == "typ" ]] && inotify_recurse=( -r )

  if _hxp_need_cmd watchexec && [[ "$HXP_NO_WATCHEXEC" != "1" ]]; then
    (( quiet == 0 )) && print -- "wpdf: watchexec mode"
    # -n avoids shell word splitting.
    watchexec \
      -n \
      --debounce 50ms \
      --postpone \
      --on-busy-update=queue \
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

  local changed _drain
  while IFS= read -r changed; do
    _hxp_watch_match "$ext" "$changed" || continue
    while IFS= read -r -t 0.05 _drain 2>/dev/null; do :; done

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

  local -x HXP_EDITOR="${HXP_EDITOR:-}"

  while [[ "$1" == -* ]]; do
    case "$1" in
      --doctor)  _hxp_doctor; return 0 ;;
      --keep-last-good) local -x HXP_KEEP_LAST_GOOD=1; shift ;;
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
  [[ -z "$src" ]] && { print -u2 "usage: hxp [--micro|--helix] [--keep-last-good] <file.{md,tex,typ}>  |  hxp --doctor"; return 2; }

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

  # Capture focus before launching the preview.
  local editor_wid; editor_wid="$(_hxp_editor_window_id)"

  local -x HXP_SESSION_SRC="$src"
  local viewer; viewer="$(_hxp_viewer)" || { print -u2 -- "hxp: no usable PDF viewer"; return 2; }
  local preview_dir="" preview_pane="" preview_shell=""

  local state_file; state_file="$(_hxp_state_file "$src")"
  mkdir -p -- "${state_file:h}" 2>/dev/null
  {
    print -r -- "src=$src"
    print -r -- "pdf=$pdf"
    print -r -- "editor=$editor"
    print -r -- "tmux=$TMUX"
    print -r -- "tmux_pane=$TMUX_PANE"
    print -r -- "windowid=$editor_wid"
    print -r -- "pid=$$"
    print -r -- "pid_start=$(_hxp_proc_start $$)"
  } >| "$state_file" 2>/dev/null

  local initial_ok=0
  if _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" \
      "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null; then
    initial_ok=1
  fi

  if [[ "$viewer" == fancy-cat ]]; then
    if _hxp_start_split; then
      print -r -- "viewer_socket=$preview_dir/socket" >> "$state_file"
      print -r -- "viewer_pane=$preview_pane" >> "$state_file"
      [[ -z "$TMUX" ]] && print -r -- "ghostty_split=1" >> "$state_file"
    else
      _hxp_release_split
      viewer="$(_hxp_gui_viewer)" || {
        print -u2 -- 'hxp: could not start fancy-cat in a right split and no fallback viewer is installed'
        _hxp_sweep_artifacts "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_gz" "$build_dir"
        rm -f -- "$state_file"
        return 2
      }
      print -u2 -- "hxp: could not start fancy-cat in a right split; using $viewer"
    fi
  fi
  print -r -- "viewer=$viewer" >> "$state_file"

  if [[ "$viewer" != fancy-cat ]]; then
    if [[ -n "$editor_wid" ]]; then
      _hxp_wmctrl_tile "$editor_wid" left id
    else
      _hxp_wmctrl_tile :ACTIVE: left
    fi
  fi

  local before_windows="" viewer_wid="" zpid="" track_window=0 launch_lockfd=""
  local launch_lock="${state_file:h}/viewer-launch.lock"
  if [[ "$viewer" != fancy-cat ]] && command -v wmctrl >/dev/null 2>&1 && wmctrl -l >/dev/null 2>&1; then
    # Serialize launches to preserve window ownership.
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
      zathura) zathura "$pdf" >/dev/null 2>&1 &!; zpid=$! ;;
    esac
    if (( track_window )); then
      viewer_wid="$(_hxp_wait_for_viewer_window "$viewer" "$zpid" "$pdf" "$before_windows")"
    fi
  } always {
    [[ -n "$launch_lockfd" ]] && zsystem flock -u "$launch_lockfd"
  }
  print -r -- "viewer_pid=$zpid" >> "$state_file" 2>/dev/null
  print -r -- "viewer_windowid=$viewer_wid" >> "$state_file" 2>/dev/null
  [[ -n "$viewer_wid" ]] && _hxp_wmctrl_tile "$viewer_wid" right id

  HXP_VIEWER_PID=$zpid HXP_VIEWER_KIND=$viewer HXP_VIEWER_SOCKET="${preview_dir:+$preview_dir/socket}" \
    wpdf -q --no-initial "$src" >/dev/null 2>&1 &!
  local wpid=$!


  local watchdog_pid=""
  cleanup() {
    [[ -n "$watchdog_pid" ]] && kill -TERM "$watchdog_pid" 2>/dev/null
    [[ -n "$wpid" ]] && { pkill -TERM -P "$wpid" 2>/dev/null; kill -TERM "$wpid" 2>/dev/null; }

    if [[ "$viewer" == fancy-cat ]]; then
      _hxp_release_split
    else
      _hxp_close_viewer "$viewer" "$zpid" "$viewer_wid"
    fi

    rm -f -- "$temp_pdf" "${temp_pdf:r}.watch.pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_tex" "$synctex_gz" 2>/dev/null
    rm -rf -- "$build_dir" 2>/dev/null
    [[ -n "$state_file" ]] && rm -f -- "$state_file" "$state_file.buf" 2>/dev/null
    rm -f -- "${$(_hxp_state_file "$pdf"):r}.pdftext" 2>/dev/null
  }

  trap 'cleanup; return 130' INT
  trap 'cleanup; return 143' TERM HUP

  if [[ "$viewer" != fancy-cat && -n "$editor_wid" && "$HXP_NO_TILE" != "1" ]] && command -v wmctrl >/dev/null 2>&1; then
    wmctrl -ia "$editor_wid" >/dev/null 2>&1
  fi

  if [[ -t 0 ]] && zmodload zsh/system 2>/dev/null; then
    # Capture the parent PID before background argument expansion.
    local shell_pid="$sysparams[pid]"
    {
      _hxp_hangup_watchdog "$shell_pid" "${editor_bin:t}" ${${(M)editor_bin:#hx}:+helix} &&
        { trap '' HUP INT TERM; cleanup }
    } &!
    watchdog_pid=$!
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

# Resume once at the first prompt, after startup files load.
if [[ -o interactive && -n ${HXP_RESUME-} ]]; then
  typeset -ga _hxp_resume=(--helix -- "$HXP_RESUME")
  [[ ${HXP_RESUME_EDITOR-} == micro ]] && _hxp_resume[1]=--micro
  unset HXP_RESUME HXP_RESUME_EDITOR
  _hxp_resume_run() {
    add-zsh-hook -d precmd _hxp_resume_run
    local -a args=("${_hxp_resume[@]}")
    unset _hxp_resume
    (( $+functions[hxp] )) || return 0
    print -rs -- hxp "${(q-)args[@]}"
    hxp "${args[@]}"
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _hxp_resume_run
fi
