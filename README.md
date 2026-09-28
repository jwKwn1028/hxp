# hxp

Personal live PDF preview for **Markdown, LaTeX, and Typst**. Edit in Helix or
Micro; saves recompile the PDF in Zathura or Sioyek. Compile errors appear in
the preview.

[Manual](manual.md) · [PDF manual](manual.pdf)

## Install

```sh
git clone https://github.com/jwKwn1028/hxp.git ~/Applications/hxp
~/Applications/hxp/install.sh
```

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

Use **tmux** for PDF-to-editor jumps into the running editor. Bind a key for
[editor-to-PDF search](manual.md#forward-search-editor--pdf).
