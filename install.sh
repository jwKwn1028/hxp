#!/usr/bin/env bash
# Install symlinks with backups; --no-config skips viewer configs.

set -euo pipefail

print_deps() {
  cat <<'EOF'
Dependencies (package manager):

  Required: zsh, pandoc, inotify-tools, helix (hx) or micro.
  Builds:   latexmk for .tex/Markdown SyncTeX; xelatex for Unicode/CJK;
            typst for .typ; watchexec for debounced watching.
  Viewers:  fancy-cat fork (--listen/--remote), or zathura/sioyek.
  X11:      wmctrl/xprop for placement; wmctrl for forward-search focus;
            xdotool for native Ghostty splits and editor keystrokes.
  Search:   python3 for fancy-cat inverse lookup; tmux for editor-pane jumps;
            pdftotext (poppler-utils) for Typst forward search;
            gdbus (glib2) for Typst → Zathura paging.
  CJK:      fonts-noto-cjk, or HXP_CJK_FONT.

Any POSIX awk works. Run hxp --doctor to check available features.
EOF
}

config=1
for arg in "$@"; do
  case "$arg" in
    --deps | -d) print_deps; exit 0 ;;
    --no-config) config=0 ;;
    *) echo "usage: install.sh [--deps] [--no-config]" >&2; exit 2 ;;
  esac
done

repo="$(cd -- "$(dirname -- "$0")" && pwd)"
ts="$(date +%Y%m%d-%H%M%S)"

link() {
  local src="$1" dst="$2"
  mkdir -p -- "$(dirname -- "$dst")"

  if [[ -L "$dst" ]]; then
    if [[ "$(readlink -- "$dst")" == "$src" ]]; then
      printf '  [ok]    %s -> %s\n' "$dst" "$src"
      return 0
    fi
    printf '  [relink] %s (was -> %s)\n' "$dst" "$(readlink -- "$dst")"
    rm -- "$dst"
  elif [[ -e "$dst" ]]; then
    local bak="$dst.bak.$ts"
    printf '  [backup] %s -> %s\n' "$dst" "$bak"
    mv -- "$dst" "$bak"
  fi

  ln -s -- "$src" "$dst"
  printf '  [link]   %s -> %s\n' "$dst" "$src"
}

echo "Linking hxp from $repo into $HOME …"
link "$repo/zsh/hxp-main.zsh"             "$HOME/.zsh/hxp-main.zsh"
link "$repo/zsh/hxp-lib.zsh"              "$HOME/.zsh/hxp-lib.zsh"
link "$repo/bin/hxp-compile"              "$HOME/.local/bin/hxp-compile"
link "$repo/bin/hxp-first-error"          "$HOME/.local/bin/hxp-first-error"
link "$repo/bin/hxp-jump"                 "$HOME/.local/bin/hxp-jump"
link "$repo/bin/hxp-inverse"              "$HOME/.local/bin/hxp-inverse"
link "$repo/bin/hxp-mdline"               "$HOME/.local/bin/hxp-mdline"
link "$repo/bin/hxp-fwd"                  "$HOME/.local/bin/hxp-fwd"
link "$repo/bin/hxp-texline"              "$HOME/.local/bin/hxp-texline"
link "$repo/bin/hxp-typtext"              "$HOME/.local/bin/hxp-typtext"
link "$repo/bin/hxp-dual-panelify"        "$HOME/.local/bin/hxp-dual-panelify"
link "$repo/bin/hxp-sessions"             "$HOME/.local/bin/hxp-sessions"
link "$repo/bin/hxp-resume"               "$HOME/.local/bin/hxp-resume"
link "$repo/config/micro/plug/hxpfwd"     "$HOME/.config/micro/plug/hxpfwd"
if (( config )); then
  link "$repo/config/zathura/zathurarc"   "$HOME/.config/zathura/zathurarc"
  link "$repo/config/sioyek/prefs_user.config" "$HOME/.config/sioyek/prefs_user.config"
  link "$repo/config/sioyek/keys_user.config" "$HOME/.config/sioyek/keys_user.config"
else
  echo "  [skip]   Zathura and Sioyek configs (--no-config)"
fi

cat <<'EOF'

Done. Add to ~/.zshrc and reload; keep ~/.local/bin on PATH:

  [[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"

Forward search bindings:

  Helix — ~/.config/helix/config.toml:
    [keys.normal]
    "C-l" = ":sh hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}"

  Micro — ~/.config/micro/bindings.json (plugin installed; goto is Ctrl-e goto):
    "Ctrl-l": "command:hxpfwd"

  Native Ghostty/X11 — ~/.config/ghostty/config:
    keybind = ctrl+shift+h=goto_split:left

See manual.md for search, splits, and troubleshooting.
EOF

print_deps
