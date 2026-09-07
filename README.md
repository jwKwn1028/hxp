# hxp

- Mostly for personal use

Live-preview workflow for **Markdown**, **LaTeX**, and **Typst**. You edit in
[helix] — or [micro], with `--micro` — on the left, a PDF viewer auto-reloads on
the right, and every save recompiles. Compile errors are rendered *into the PDF*
(and optionally into a side terminal pane), so you fix and re-save without
leaving the editor. Click in the PDF to jump back to the source line, or press
`Ctrl-l` in the editor to move the PDF to your cursor.

Glued together from [pandoc], [latexmk], [typst], and [zathura] or [sioyek].

> **[📖 Read the manual →](manual.md)** ([PDF](manual.pdf))
>
> The operational reference: every command and flag, both directions of synctex
> search, per-language behavior, viewer keybindings, error reporting,
> environment variables, window tiling, runtime files, and troubleshooting.
> This page is just the front door.

[helix]:   https://helix-editor.com
[micro]:   https://micro-editor.github.io
[pandoc]:  https://pandoc.org
[latexmk]: https://www.cantab.net/users/johncollins/latexmk/
[typst]:   https://typst.app
[zathura]: https://pwmt.org/projects/zathura/
[sioyek]:  https://sioyek.info

## Install

```sh
git clone https://github.com/jwKwn1028/hxp.git ~/Applications/hxp
~/Applications/hxp/install.sh
```

Then add one line to `~/.zshrc` and reload your shell:

```zsh
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"
```

`install.sh` symlinks the shell functions, the `bin/` helpers, the viewer
configs, and micro's forward-search plugin into `$HOME`. It's re-runnable and
backs up any real file it would replace to `*.bak.<timestamp>`.

Two things it can't do for you:

- **`~/.local/bin` must be on `PATH` before a viewer starts**, or inverse search
  silently falls back to opening a fresh editor.
- **Forward search needs a keybinding you add yourself** — one line for helix,
  one for micro. `install.sh` prints both; the manual explains
  [why](manual.md#forward-search-editor--pdf).

## Use

```sh
hxp notes.md             # editor left, PDF right, recompile on save
hxp --micro paper.tex    # the same session in micro instead of helix
hxp slides.typ           # .md / .tex / .typ; scaffolds the file if it's new
wpdf notes.md            # just the watcher — no editor, no viewer
hxp_errs paper.tex       # live error readout, for a second tmux pane
hxp --doctor             # what's installed, and what each missing tool costs
```

Quitting the editor tears the session down: watcher stopped, viewer window
closed, scratch files swept — **keeping only the finished `.pdf`**.

Run it inside **tmux** if you want inverse search to land in the editor you
already have open. See [the recommended layout](manual.md#the-recommended-tmux-layout).

## Dependencies

Required: `zsh`, `pandoc`, `inotify-tools`, and an editor — `helix` by default,
`micro` if you use `--micro`. Only the one you use needs to be installed.

Recommended: `watchexec`, `latexmk`, `xelatex`, `typst`, `sioyek` or `zathura`,
`wmctrl` + `xprop` (X11 tiling), and `tmux` / `xdotool` (in-place inverse
search). Any `awk` works — no gawk-only features.

Full annotated list: `./install.sh --deps`. What your machine actually has:
`hxp --doctor`.

## Layout

```
hxp/
├── manual.md          # the reference — start there
├── install.sh         # symlinks everything into $HOME (also: --deps)
├── zsh/
│   ├── hxp-main.zsh   # hxp() / wpdf(), editor + viewer launch, tiling
│   └── hxp-lib.zsh    # compile, error rendering, hxp_errs, --doctor
├── bin/
│   ├── hxp-compile        # per-save wrapper watchexec calls
│   ├── hxp-jump           # synctex inverse search (PDF -> editor)
│   ├── hxp-fwd            # synctex forward search (editor -> PDF)
│   ├── hxp-mdline         # md <- tex line mapping (jump + error renderer)
│   ├── hxp-texline        # md -> tex line mapping (forward search)
│   ├── hxp-typtext        # typ -> searchable page text (typst has no synctex)
│   └── hxp-dual-panelify  # sioyek dual-panel wrapper
├── config/
│   ├── zathura/, sioyek/  # viewer prefs + reverse-search wiring
│   └── micro/plug/hxpfwd/ # forward-search command for micro
└── test/
    ├── parse-test.zsh     # toolchain-free: log parsers, editor dispatch
    └── smoke.zsh          # real compile per language
```

`hxp-main.zsh` sources `hxp-lib.zsh`; the compile helpers live in the lib so
`hxp-compile` (run on every save) can load them without the rest of `.zshrc`.

## Tests

```sh
zsh test/parse-test.zsh   # fast gate — needs no compilers, runs under every awk
zsh test/smoke.zsh        # real pipeline; skips languages whose tools are absent
```

Both run on every push via `.github/workflows/ci.yml`.
