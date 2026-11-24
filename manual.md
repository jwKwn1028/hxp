# hxp manual

Markdown, LaTeX, and Typst editing with Helix/Micro and live PDF preview.

## Setup

Follow [installation](README.md#install), then run `hxp --doctor`.
The installer links helpers, the Micro plugin, and viewer configs; `--no-config`
skips Zathura/Sioyek configs. Existing files become `*.bak.<timestamp>`.
Rerun after updates. Dependencies: `./install.sh --deps`.

## Commands

```sh
hxp notes.md                 # Helix, preview, watcher
hxp --micro paper.tex        # Micro
hxp --helix slides.typ       # override HXP_EDITOR
hxp --keep-last-good FILE    # preserve a good PDF on failure
wpdf [-q] [--no-initial] FILE # watcher only
hxp_errs FILE                # live diagnostics alongside hxp/wpdf
```

Files may be `.md`, `.tex`, or `.typ`. `hxp` creates missing sources and builds
before opening the editor; initial failures also open diagnostics.
`wpdf -q` hides status; `--no-initial` skips its first build.

## Preview splits

fancy-cat opens right of the editor. tmux keeps editor focus. Native X11 Ghostty
uses `Ctrl+Shift+O` to split and needs this binding in `~/.config/ghostty/config`:

```text
keybind = ctrl+shift+h=goto_split:left
```

Keep only the editor and preview splits, and source hxp in each split's zsh.
Ghostty inverse search relies on focus and the editor being left of the preview.
Failed splits are closed; hxp falls back to Zathura, then Sioyek.
`HXP_NO_SPLIT=1` forces a GUI viewer. Floating X11 windows use `wmctrl`/`xprop`;
tiling WMs place them; Wayland placement is manual.

Quitting or closing the editor stops the watcher and removes scratch files,
keeping the PDF. Terminal hangups trigger cleanup within about a second;
detaching tmux leaves hxp running. Shared Sioyek windows with uncertain ownership
stay open. Typst watches incrementally; other builds use watchexec (50ms debounce)
or inotifywait. Generated files are ignored and PDFs are replaced atomically.
hxp notifies its fancy-cat preview after publishing success or error PDFs,
including native Typst output. Updated forks reload immediately; polling remains
the fallback.

## Inverse search (PDF → editor)

| Viewer | Trigger |
|---|---|
| fancy-cat | Ctrl+L at pointer/view centre; Ctrl+click on release |
| Sioyek | `F5` at pointer, or Ctrl+click |
| Zathura | Ctrl+click |

Keep `hxp-jump`, `hxp-inverse`, and Python 3 on `PATH`. fancy-cat Ctrl+L and Typst
lookup require the fork's `--inverse-search-resolver` and `inverse_search` action
(default `<C-l>`, configurable in `KeyMap`). Older builds support SyncTeX clicks.

LaTeX uses SyncTeX; Markdown also needs latexmk and approximate source mapping.
Typst matches prose in the root and literal local includes/imports, including
root-relative paths. Code, comments, strings, math, and raw text are excluded;
citations within prose are tolerated. Repeated or unmatched text reports
`AmbiguousSourceText` or `NoMatchingSourceText`; dynamic/generated content may
not map. LaTeX/Markdown misses report `NoSyncTeXSourceLocation`.

tmux targets recorded panes on the recorded server. Ctrl+click also needs this
binding; reload with `tmux source-file ~/.tmux.conf`:

```tmux
bind -n C-MouseDown1Pane if -F -t = '#{mouse_any_flag}' { send-keys -M } { swap-pane -s @ }
```

It forwards clicks to mouse-aware apps and keeps tmux's shell-pane behavior.
Use tmux when focus follows the mouse. Each fancy-cat preview targets its own
session; unreachable editors report failure. GUI viewers can spawn an editor
only when the helper has a terminal; X11 otherwise uses `xdotool`.

## Forward search (editor → PDF)

Helix, `~/.config/helix/config.toml`:

```toml
[keys.normal]
"C-l" = ":sh ~/.local/bin/hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}"
```

Micro, `~/.config/micro/bindings.json`:

```json
"Ctrl-l": "command:hxpfwd"
```

The installed Micro plugin runs asynchronously; its old goto prompt remains at
`Ctrl-e goto`. `hxp-fwd FILE LINE [COL]` targets the session preview. Markdown
maps through generated TeX. Typst caches `pdftotext` output per PDF build and
uses nearby lines to break ties (earliest page wins remaining ties). fancy-cat
and Sioyek highlight matches; Zathura pages through `gdbus`. Math/generated text
may not match. In tmux, successful searches select the preview pane.

## Viewer keybindings

Sioyek adds `F5` inverse search, `i` dark colors, `a` fit width, `Ctrl-d/u`
half-pages, `J/K` next/previous page, `H/L` page top/bottom, `'` mark, and
`Ctrl-l` reload. Other defaults remain. Zathura uses stock bindings with
clipboard selection, SyncTeX, incremental search, fit width, and a hidden status
bar. Both reload automatically; sessions open separate previews.

Optional Sioyek dual-panel support:

```sh
venv="${XDG_DATA_HOME:-$HOME/.local/share}/sioyek-extensions"
python3 -m venv "$venv"
"$venv/bin/python" -m pip install sioyek
```

Uncomment `_dual_panelify d` in `config/sioyek/keys_user.config`.
Override the venv with `HXP_SIOYEK_VENV`.

## Builds

| Source | Build | Root |
|---|---|---|
| `.md` | Pandoc → LaTeX → latexmk; direct Pandoc fallback without SyncTeX | Opened file |
| `.tex` | `latexmk -pdf -synctex=1` | Opened `\documentclass` source, or nearest `main.tex`, `root.tex`, `thesis.tex` containing it |
| `.typ` | `typst watch` | Nearest `main.typ`; `typst.toml` stops upward search |

PDFs live beside the root. Builds run there; Typst uses it as `--root`.
LaTeX defaults to pdflatex (`latexmkrc` can override); a sibling bibliography
enables `-bibtex`. Source, bibliography, `.sty`, and `.cls` edits trigger rebuilds.
`HXP_NO_NATIVE_TYP=1` uses full Typst rebuilds.

Markdown uses xelatex, lualatex, then pdflatex; supports `\(…\)`/`\[…\]` math
and blue links. Frontmatter `bibliography:` overrides automatic loading of the
first sibling `.bib`. `geometry:` overrides `HXP_MD_MARGIN` (default `0.75in`);
use `2cm` or `top=2cm,left=3cm`, or empty for class defaults.

CJK fonts are detected once per watcher and loaded for Han, kana, or Hangul in
the source or local bibliographies. Bibliography paths accept scalars/lists and
resolve relative to the Markdown file. `HXP_CJK_FONT` or `CJKmainfont:` forces
the chosen font.

## Errors

Helix: `:open %sh{hxp-first-error}`. Micro: `Ctrl-e hxperror`.
Markdown jumps are approximate; unmapped errors open the Markdown file, while
errors without a source location have no jump target. `hxp_errs FILE` shows live
diagnostics in another pane.

Failures normally replace the preview with an error PDF containing the message,
location, context, and log extract; Markdown adds generated TeX context.
Typst renders these when available, otherwise Pandoc/LaTeX does.
`--keep-last-good` keeps a good PDF and updates diagnostics. Before any successful
build, it displays and refreshes error PDFs.

## Environment variables

| Variable | Effect |
|---|---|
| `HXP_EDITOR` | `helix` (default/fallback) or `micro` |
| `HXP_VIEWER` | GUI preference: `zathura` or `sioyek` |
| `HXP_CJK_FONT` | Markdown CJK font |
| `HXP_MD_MARGIN` | Geometry; default `0.75in` |
| `HXP_NO_SPLIT=1` | Use a GUI viewer |
| `HXP_KEEP_LAST_GOOD=1` | Preserve good PDFs on failure |
| `HXP_NO_NATIVE_TYP=1` | Full Typst rebuilds |
| `HXP_NO_WATCHEXEC=1` | Use inotifywait |
| `HXP_NO_TILE=1` | Disable GUI placement |
| `HXP_WM` | Force `tiling` or `floating` |
| `HXP_SIOYEK_VENV` | Sioyek extensions venv |
| `HXP_AWK` | Awk binary |

## Runtime files

`<runtime>` means `${XDG_RUNTIME_DIR:-/tmp}/hxp`; keys are SHA-1 path hashes.

| Path | Purpose |
|---|---|
| `<root-stem>.pdf` | Output, kept on exit |
| `<src-dir>/.<stem>.error.log`, `.error.md`, `.debug.tex` | Diagnostics |
| `<src-dir>/.<stem>.tmp.pdf`, `.tmp.watch.pdf` | Publication/staging |
| `<src-dir>/.hxp_build_<stem>/` | latexmk output and `.hxp.tex` |
| `<pdf-dir>/<root-stem>.synctex.gz` | Search data, removed on exit |
| `<runtime>/<sha1>.state`, `.state.buf` | Session targets; Micro buffer |
| `<runtime>/<sha1>.errpdf`, `.pdftext` | Error-page identity; cached PDF text |
| `<runtime>/fonts/`, `errdoc.*/` | Error-page fonts and temporary reports |
| `<runtime>/viewer-launch.lock` | Shared startup lock |

Crash leftovers may be deleted; sessions recreate them.

## tmux restore

`hxp-sessions` emits tab-separated `TMUX_SOCKET TMUX_PANE EDITOR VIEWER
VIEWER_SOCKET SOURCE`. The tmux-resurrect save hook stores editor panes as shells
and fancy-cat panes as `hxp-resume PANE_INDEX EDITOR SOURCE`; add `hxp-resume` to
`@resurrect-processes`. Restore waits for `@resurrect-restoring` to clear and a
Ghostty client, then restarts hxp in an idle editor pane. While waiting,
`@hxp-resume` holds `EDITOR_PANE_ID EDITOR SOURCE` for subsequent saves.

## Troubleshooting

Start with `hxp --doctor`.

| Problem | Check |
|---|---|
| No updates | Watch tools; try `HXP_NO_WATCHEXEC=1` |
| Wrong/new editor | Use tmux or `xdotool`; check helper `PATH` |
| tmux Ctrl+click fails | Add the mouse binding above, or use Ctrl+L |
| fancy-cat Ctrl+L fails | Update the fork and restart hxp |
| `NoLiveSourceSession` | Restart hxp |
| `AmbiguousSourceText` | Choose distinctive prose |
| Ghostty types into preview | Add the left-focus binding; keep two splits |
| Markdown search fails | Install latexmk |
| Typst search fails | Install `pdftotext`; Zathura also needs `gdbus` |
| Missing CJK | Install `fonts-noto-cjk` or set `HXP_CJK_FONT` |
| Unknown Micro `hxpfwd` | Rerun installer; add binding |
| Micro jump inserts commands | Undo; bind `Ctrl-e` to `CommandMode` |
| Wrong Zathura preview | Restart hxp from a freshly loaded shell |
| Sioyek reuses a window | Remove single-window overrides |

## Development

```sh
zsh test/parse-test.zsh
zsh test/workflow-test.zsh
python3 -B test/inverse-test.py
python3 -B test/search-tmux-test.py
zsh test/smoke.zsh
bash test/sessions-test.sh
bash test/resume-test.sh
```

CI runs all suites. Smoke tests compile available languages; tmux tests use
private servers and exercise installed editors. `zsh/hxp-main.zsh` owns sessions;
`hxp-lib.zsh` handles builds/errors. Search and restore helpers live in `bin/`;
Micro integration is in `config/micro/plug/hxpfwd/`.

## Uninstall

Remove the source line from `~/.zshrc` and these symlinks; restore backups as needed:

```sh
rm -f ~/.zsh/hxp-main.zsh ~/.zsh/hxp-lib.zsh \
      ~/.local/bin/hxp-compile ~/.local/bin/hxp-first-error ~/.local/bin/hxp-jump \
      ~/.local/bin/hxp-inverse ~/.local/bin/hxp-mdline ~/.local/bin/hxp-fwd \
      ~/.local/bin/hxp-texline ~/.local/bin/hxp-typtext \
      ~/.local/bin/hxp-dual-panelify ~/.local/bin/hxp-sessions ~/.local/bin/hxp-resume \
      ~/.config/zathura/zathurarc ~/.config/sioyek/prefs_user.config \
      ~/.config/sioyek/keys_user.config ~/.config/micro/plug/hxpfwd
```
