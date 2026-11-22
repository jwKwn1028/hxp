# hxp

Edit **Markdown, LaTeX, and Typst** in Helix or Micro. On save, fancy-cat updates
the preview in a right-hand Ghostty or tmux split. Fallbacks are Zathura, then Sioyek.

[Manual](manual.md) · [PDF manual](manual.pdf)

## Install

```sh
git clone https://github.com/jwKwn1028/hxp.git ~/Applications/hxp
~/Applications/hxp/install.sh
```

Rerun `install.sh` after updating hxp to pick up new helper symlinks;
`--no-config` leaves the Zathura and Sioyek configs to your dotfiles. In the
chezmoi setup, `chezmoi apply` clones hxp at a pinned commit, runs
`install.sh --no-config`, and installs the Helix and Micro F8 bindings.

Add to `~/.zshrc`, ensure `~/.local/bin` is on `PATH`, and reload:

```zsh
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"
```

Dependencies: `./install.sh --deps`. Check your setup: `hxp --doctor`.

## Use

```sh
hxp notes.md            # Helix + PDF preview
hxp --micro paper.tex   # use Micro
hxp slides.typ
wpdf notes.md           # watch only
hxp_errs paper.tex      # live errors in another pane
```

Ctrl+click typeset text to jump to its source with SyncTeX. For the reverse
direction, bind an [editor-to-PDF search key](manual.md#forward-search-editor--pdf).
