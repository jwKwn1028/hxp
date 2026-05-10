#!/usr/bin/env bash
# Install hxp by symlinking the repo's tracked files into the standard
# locations under $HOME. Re-runnable: existing files get backed up to
# *.bak.<timestamp> on the first run, and existing symlinks pointing at
# this repo are left alone.

set -euo pipefail

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
link "$repo/config/zathura/zathurarc"     "$HOME/.config/zathura/zathurarc"
link "$repo/config/sioyek/prefs_user.config" "$HOME/.config/sioyek/prefs_user.config"

cat <<'EOF'

Done. Final step (one-time):

  Add the following line to ~/.zshrc, then reload your shell:

      [[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"

  Verify ~/.local/bin is on PATH; if not, add it before zathura/sioyek
  spawn so synctex reverse-search can find hxp-jump.

Dependencies (install via your package manager):
  required: zsh, helix (hx), pandoc, inotify-tools (inotifywait)
  recommended: watchexec, xelatex (texlive-xetex), latexmk, typst,
               wmctrl, xprop, sioyek or zathura
  CJK font (for Korean/Japanese/Chinese in markdown PDFs):
               fonts-noto-cjk  -- or set HXP_CJK_FONT to your preference
EOF
