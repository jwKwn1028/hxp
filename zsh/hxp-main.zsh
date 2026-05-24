# ~/.zsh/hxp-main.zsh
# Top-level entrypoints for the hxp / wpdf live preview workflow. Sourced
# by .zshrc with a single line — the actual functions live here so the
# config can be tracked in version control without dragging the rest of
# the user's shell setup into the repo.
#
# Layering: hxp-main.zsh sources hxp-lib.zsh (helpers used by both this
# file and the watchexec-driven hxp-compile script).

# ---------- hxp / wpdf: live editor + PDF preview ----------
# Supports markdown, latex, typst. The compile helpers live in
# ~/.zsh/hxp-lib.zsh so that ~/.local/bin/hxp-compile (driven by watchexec)
# can source them without paying the cost of the whole .zshrc.
#
# Knobs (env vars):
#   HXP_VIEWER           : force "sioyek" or "zathura"
#   HXP_VIEWER_PID       : set internally; viewer's PID (used to send SIGHUP)
#   HXP_NO_NATIVE_TYP=1  : disable `typst watch`, use generic compile loop
#   HXP_NO_WATCHEXEC=1   : disable watchexec, fall back to inotifywait
#   HXP_NO_TILE=1        : disable wmctrl tiling of editor/viewer windows
#   HXP_WM               : force "tiling" or "floating"; otherwise auto-detected.
#                          Under tiling WMs (i3, sway, bspwm, …) we skip the
#                          wmctrl -e geometry calls and let the WM (e.g.
#                          autotiling) place the viewer beside the editor.

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
  # On tiling WMs, _NET_MOVERESIZE_WINDOW is ignored for managed containers —
  # let the WM (e.g. autotiling on i3) place the window itself.
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

  local viewer="${1:l}" pid="$2" pdf="$3" base="${${pdf:t}:l}"
  local id

  if [[ -n "$pid" ]]; then
    # Require the PDF basename in the title too — sioyek's shared instance
    # may own several windows on different workspaces; last-wins on PID
    # alone would return whichever was opened most recently.
    id="$(wmctrl -lp 2>/dev/null | awk -v pid="$pid" -v base="$base" '
      BEGIN { base=tolower(base) }
      $3 == pid {
        line=tolower($0)
        if (base == "" || index(line, base) > 0) id=$1
      }
      END { if (id != "") print id }
    ')"
    [[ -n "$id" ]] && { print -r -- "$id"; return 0; }
  fi

  # Require the PDF basename in the title so concurrent hxp sessions don't
  # collide — a bare class match would pick *any* sioyek window when several
  # share one instance via --new-window.
  id="$(wmctrl -lx 2>/dev/null | awk -v viewer="$viewer" -v base="$base" '
    BEGIN { viewer=tolower(viewer); base=tolower(base) }
    {
      line=tolower($0)
      cls=tolower($3)
      if (base != "" && index(line, base) > 0) id=$1
      else if (base == "" && cls ~ viewer) id=$1
    }
    END { if (id != "") print id }
  ')"
  [[ -n "$id" ]] || return 1
  print -r -- "$id"
}

_hxp_tile_viewer_when_ready() {
  emulate -L zsh
  [[ "$HXP_NO_TILE" == "1" ]] && return 0
  # Tiling WM: skip the polling loop — autotiling already placed the viewer
  # as a sibling split of the focused editor terminal.
  [[ "$(_hxp_wm_kind)" == "tiling" ]] && return 0

  local -a wa
  wa=( $(_hxp_wmctrl_workarea) )
  (( ${#wa[@]} == 4 )) || return 0

  local viewer="$1" pid="$2" pdf="$3" id i
  for i in {1..40}; do
    id="$(_hxp_find_viewer_window "$viewer" "$pid" "$pdf")"
    if [[ -n "$id" ]]; then
      _hxp_wmctrl_tile "$id" right id
      return 0
    fi
    sleep 0.05
  done
}

# ---------- wpdf: watch + compile ----------

wpdf() {
  emulate -L zsh
  setopt pipefail

  local quiet=0
  if [[ "$1" == "-q" || "$1" == "--quiet" ]]; then
    quiet=1
    shift
  fi

  local src="$1"
  [[ -z "$src" ]] && { print -u2 -- "usage: wpdf [-q] <file.{md,tex,typ}>"; return 2; }
  [[ ! -f "$src" ]] && { print -u2 -- "wpdf: not found: $src"; return 2; }

  _hxp_need_cmd inotifywait || { print -u2 -- "wpdf: missing inotifywait (install inotify-tools)"; return 2; }
  _hxp_need_cmd pandoc     || { print -u2 -- "wpdf: missing pandoc"; return 2; }

  src="$(_hxp_abs "$src")"
  local dir="${src:h}"
  local base="${src:t}"
  local stem="${base:r}"
  local ext="${base:e}"

  local pdf="$dir/$stem.pdf"
  local temp_pdf="$dir/.${stem}.tmp.pdf"
  local err_log="$dir/.${stem}.error.log"
  local err_md="$dir/.${stem}.error.md"
  local debug_tex="$dir/.${stem}.debug.tex"
  local build_dir="$dir/.hxp_build_${stem}"

  case "$ext" in
    md) ;;
    typ) _hxp_need_cmd typst   || { print -u2 -- "wpdf: missing typst"; return 2; } ;;
    tex) _hxp_need_cmd latexmk || { print -u2 -- "wpdf: missing latexmk"; return 2; } ;;
    *)   print -u2 -- "wpdf: unsupported extension: $ext"; return 2 ;;
  esac

  trap 'rm -f -- "$temp_pdf"; exit 0' INT TERM HUP

  # Initial compile so the viewer has something to show immediately.
  _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null

  (( quiet == 0 )) && print -- "wpdf: watching $src -> $pdf"

  # Native incremental watcher for typst (much faster than full recompiles).
  if [[ "$ext" == "typ" && "$HXP_NO_NATIVE_TYP" != "1" ]]; then
    local root_src; root_src="$(_hxp_root_for "$src" typ)"
    local root_dir="${root_src:h}"

    # `typst watch` writes the PDF in-place on each successful compile.
    # Errors stream to stderr and we mirror them into err_log; the PDF stays
    # at the last known-good build (zathura/sioyek auto-reload picks it up).
    typst watch --root "$root_dir" "$root_src" "$pdf" 2>"$err_log"
    return
  fi

  # Generic watch loop (md, tex, and typ when native disabled).
  # Prefer `watchexec` — kernel-level debouncing, follows symlinks,
  # respects gitignore, handles editor swap-file dance better than raw
  # inotifywait. Falls back to inotifywait when not installed.
  if _hxp_need_cmd watchexec && [[ "$HXP_NO_WATCHEXEC" != "1" ]]; then
    (( quiet == 0 )) && print -- "wpdf: watchexec mode"
    exec watchexec \
      --debounce 250ms \
      --postpone \
      --no-process-group \
      --no-vcs-ignore \
      --quiet \
      -w "$dir" \
      --filter "$base" \
      -- hxp-compile "$src" "$ext" "$dir" "$stem" \
                    "$pdf" "$temp_pdf" "$err_log" "$err_md" \
                    "$debug_tex" "$build_dir"
  fi

  # Fallback: inotifywait with a manual 200ms drain.
  local changed _drain
  while IFS= read -r changed; do
    [[ "$changed" != "$src" ]] && continue
    while IFS= read -r -t 0.2 _drain 2>/dev/null; do :; done

    # If the source was removed (rm, or atomic-rename gone wrong), stop
    # rather than burning compiles on a missing file. The user's next
    # `hxp` invocation will re-scaffold or open the new path cleanly.
    [[ -f "$src" ]] || { (( quiet == 0 )) && print -- "wpdf: source vanished, exiting"; break; }

    if _hxp_compile_once "$src" "$ext" "$dir" "$stem" "$pdf" "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$build_dir" >/dev/null; then
      (( quiet == 0 )) && print -- "wpdf: OK  $(date +%H:%M:%S)"
    else
      (( quiet == 0 )) && print -- "wpdf: ERR $(date +%H:%M:%S)  (see $err_log)"
    fi
  done < <(
    inotifywait -m -q \
      -e close_write -e moved_to \
      --format '%w%f' "$dir"
  )
}


hxp() {
  emulate -L zsh
  setopt pipefail
  unsetopt monitor

  local src="$1"
  [[ -z "$src" ]] && { print -u2 "usage: hxp <file.{md,tex,typ}>"; return 2; }

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

  # For tex/typ, the PDF actually lives next to the project root, not the
  # opened file. Compute that so the viewer points at the right artifact.
  local root_src; root_src="$(_hxp_root_for "$src" "$ext")"
  local root_dir="${root_src:h}"
  local root_stem="${${root_src:t}:r}"
  local pdf_dir pdf_stem
  if [[ "$ext" == "tex" || "$ext" == "typ" ]]; then
    pdf_dir="$root_dir"; pdf_stem="$root_stem"
  else
    pdf_dir="$dir"; pdf_stem="$stem"
  fi

  local pdf="$pdf_dir/$pdf_stem.pdf"
  local temp_pdf="$dir/.${stem}.tmp.pdf"
  local err_log="$dir/.${stem}.error.log"
  local err_md="$dir/.${stem}.error.md"
  local debug_tex="$dir/.${stem}.debug.tex"
  local build_dir="$dir/.hxp_build_${stem}"
  local synctex_tex="$build_dir/${stem}.hxp.tex"
  local synctex_gz="$pdf_dir/$pdf_stem.synctex.gz"

  # Resolve the editor terminal's X11 window ID before anything else moves
  # focus. $WINDOWID is set by some terminals; _hxp_active_window_id falls
  # back to xprop _NET_ACTIVE_WINDOW for terminals that don't.
  local editor_wid; editor_wid="$(_hxp_editor_window_id)"

  # State file for hxp-jump: lets PDF inverse-search drive the existing
  # helix instance instead of spawning a fresh `hx` window.
  local state_dir="${XDG_RUNTIME_DIR:-/tmp}/hxp"
  mkdir -p -- "$state_dir" 2>/dev/null
  local state_key state_file
  # printf '%s' (no trailing newline) so the digest matches what hxp-jump
  # computes from the synctex-supplied path. `print -r --` adds a newline
  # and would silently break the lookup.
  state_key="$(printf '%s' "$src" | sha1sum | cut -d' ' -f1)"
  state_file="$state_dir/$state_key.state"
  {
    print -r -- "src=$src"
    print -r -- "pdf=$pdf"
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

  local viewer; viewer="$(_hxp_viewer)"
  case "$viewer" in
    sioyek)
      sioyek --new-window "$pdf" >/dev/null 2>&1 &!
      # Auto-enable synctex mode so right-click triggers inverse search
      # without needing to press F4 first.
      { sleep 0.5 && sioyek --execute-command toggle_synctex --nofocus; } >/dev/null 2>&1 &!
      ;;
    zathura|*) zathura "$pdf" >/dev/null 2>&1 &! ;;
  esac
  local zpid=$!
  _hxp_tile_viewer_when_ready "$viewer" "$zpid" "$pdf"

  HXP_VIEWER_PID=$zpid HXP_VIEWER_KIND=$viewer wpdf -q "$src" >/dev/null 2>&1 &!
  local wpid=$!


  cleanup() {
    [[ -n "$wpid" ]] && { pkill -TERM -P "$wpid" 2>/dev/null; kill -TERM "$wpid" 2>/dev/null; }

    # Close *our* viewer window via wmctrl first. Sioyek runs as a single
    # shared instance with one window per --new-window invocation; killing
    # the process would close concurrent hxp sessions' windows too.
    local _closed=0 _wid=""
    if command -v wmctrl >/dev/null 2>&1; then
      _wid="$(_hxp_find_viewer_window "$viewer" "$zpid" "$pdf")"
      if [[ -n "$_wid" ]] && wmctrl -ic "$_wid" 2>/dev/null; then
        _closed=1
      fi
    fi

    if (( ! _closed )); then
      [[ -n "$zpid" ]] && kill -TERM "$zpid" 2>/dev/null
      pgrep -af "(zathura|sioyek) .*${pdf}" 2>/dev/null | awk '{print $1}' | while read -r p; do
        kill -TERM "$p" 2>/dev/null
      done
    fi

    # Sweep transient build artifacts. Keep the rendered PDF — that's the
    # output the user wanted. Drop everything else: error log/markdown, the
    # .debug.tex pandoc emits for md→tex line-mapping, the latex build dir,
    # the synctex sidecar (only useful while the viewer is open), and the
    # state file used by hxp-jump.
    rm -f -- "$temp_pdf" "$err_log" "$err_md" "$debug_tex" "$synctex_tex" "$synctex_gz" 2>/dev/null
    rm -rf -- "$build_dir" 2>/dev/null
    [[ -n "$state_file" ]] && rm -f -- "$state_file" 2>/dev/null
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
      hx "$src" "$err_log" "$_dtex"
    else
      hx "$(_hxp_hx_target_for_error "$src" "$err_log")" "$err_log"
    fi
  else
    hx "$src"
  fi

  cleanup
  trap - INT TERM HUP
}
