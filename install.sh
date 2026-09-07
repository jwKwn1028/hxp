#!/usr/bin/env bash
# Install hxp by symlinking the repo's tracked files into the standard
# locations under $HOME. Re-runnable: existing files get backed up to
# *.bak.<timestamp> on the first run, and existing symlinks pointing at
# this repo are left alone.
#
# Run `./install.sh --deps` to print the dependency list without installing.

set -euo pipefail

# Canonical dependency list. The README points here so the two never drift.
print_deps() {
  cat <<'EOF'
Dependencies (install via your package manager):

  Required:
    zsh                  shell
    pandoc               markdown -> PDF pipeline
    inotify-tools        inotifywait, for the fallback watch loop
    an editor            helix (hx) by default, or micro via `hxp --micro`
                         / HXP_EDITOR=micro. Only the one you use is needed.

  Recommended:
    watchexec            kernel-level debouncing, smarter watch loop
    xelatex              Unicode-capable PDF engine (texlive-xetex)
    latexmk              .tex compile driver
    typst                .typ compiler
    sioyek or zathura    PDF viewer with reverse-search support
    wmctrl, xprop        X11 tiling; wmctrl also focuses the viewer for
                         forward search (both no-op on Wayland)

  Inverse search (PDF -> editor), optional:
    tmux                 in-place jumps into the running editor's pane
    xdotool              X11 keystroke fallback when not in tmux

  Forward search (editor -> PDF), optional:
    pdftotext            typst text-search fallback (poppler-utils)
    gdbus                pages a running zathura for typst (glib2)

  CJK markdown PDFs (Korean/Japanese/Chinese):
    fonts-noto-cjk       or set HXP_CJK_FONT to a preferred family

  Note: any awk works (gawk/mawk/busybox) — no gawk-only features are used.
  Run `hxp --doctor` after install to see which features are active.
EOF
}

if [[ "${1:-}" == "--deps" || "${1:-}" == "-d" ]]; then
  print_deps
  exit 0
fi

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
link "$repo/bin/hxp-jump"                 "$HOME/.local/bin/hxp-jump"
link "$repo/bin/hxp-mdline"               "$HOME/.local/bin/hxp-mdline"
link "$repo/bin/hxp-fwd"                  "$HOME/.local/bin/hxp-fwd"
link "$repo/bin/hxp-texline"              "$HOME/.local/bin/hxp-texline"
link "$repo/bin/hxp-typtext"              "$HOME/.local/bin/hxp-typtext"
link "$repo/bin/hxp-dual-panelify"        "$HOME/.local/bin/hxp-dual-panelify"
link "$repo/config/zathura/zathurarc"     "$HOME/.config/zathura/zathurarc"
link "$repo/config/sioyek/prefs_user.config" "$HOME/.config/sioyek/prefs_user.config"
link "$repo/config/sioyek/keys_user.config" "$HOME/.config/sioyek/keys_user.config"
# micro's half of forward search. helix can pass its cursor position to a shell
# command from a keybinding; micro cannot, so the call comes from a plugin.
link "$repo/config/micro/plug/hxpfwd"     "$HOME/.config/micro/plug/hxpfwd"

cat <<'EOF'

Done. Final step (one-time):

  Add the following line to ~/.zshrc, then reload your shell:

      [[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"

  Verify ~/.local/bin is on PATH; if not, add it before zathura/sioyek
  spawn so synctex reverse-search can find hxp-jump.

  For forward search (cursor -> PDF), bind a key in your editor. hxp ships
  the shim, not the binding.

  helix — ~/.config/helix/config.toml:

      [keys.normal]
      "C-l" = ":sh hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}"

  micro — ~/.config/micro/bindings.json (the hxpfwd command comes from the
  plugin linked above; this replaces micro's default `goto ` prefill on
  Ctrl-l, which stays available as Ctrl-e goto):

      "Ctrl-l": "command:hxpfwd"

EOF

print_deps
