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

Rerun the installer after updates. `--no-config` preserves viewer configs;
chezmoi uses it and supplies Ctrl+L bindings. Dependencies: `./install.sh --deps`.
Check setup with `hxp --doctor`.

## Use

```sh
hxp notes.md            # Helix + preview
hxp --micro paper.tex   # Micro + preview
hxp slides.typ
wpdf notes.md           # watcher only
hxp_errs paper.tex      # live diagnostics
```

Ctrl+L follows the cursor into the PDF; in fancy-cat it returns to source.
Ctrl+click also returns to source. LaTeX/Markdown use SyncTeX; Typst matches prose.
See [search setup](manual.md#inverse-search-pdf--editor).
