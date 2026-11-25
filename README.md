# hxp

Edit **Markdown, LaTeX, or Typst** in Helix or Micro with a PDF preview.
Saves update fancy-cat in a Ghostty or tmux split; Zathura and Sioyek are fallbacks.

[Manual](manual.md) · [PDF manual](manual.pdf)

## Install

```sh
git clone https://github.com/jwKwn1028/hxp.git ~/Applications/hxp
~/Applications/hxp/install.sh
```

Add to `~/.zshrc`, put `~/.local/bin` on `PATH`, and reload:

```zsh
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"
```

Rerun the installer after updates (`--no-config` keeps viewer configs, `--deps`
installs dependencies), then check with `hxp --doctor`.

## Use

```sh
hxp notes.md            # Helix + preview
hxp --micro paper.tex   # Micro + preview
hxp slides.typ
wpdf notes.md           # watcher only
hxp_errs paper.tex      # live diagnostics
```
