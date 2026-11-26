# hxp manual

## Setup

Install per the [README](README.md#install), then run `hxp --doctor`. The
installer symlinks helpers, the Micro plugin, and viewer configs (`--no-config`
skips viewer configs), backing up existing files as `*.bak.<timestamp>`. Rerun it
after updates; `./install.sh --deps` installs dependencies.

## Commands

```sh
hxp notes.md                  # Helix + preview + watcher
hxp --micro paper.tex         # Micro
hxp --helix slides.typ        # override HXP_EDITOR
hxp --keep-last-good FILE     # keep the good PDF on failure
wpdf [-q] [--no-initial] FILE # watcher only; quiet; skip first build
hxp_errs FILE                 # live diagnostics
```

`hxp` creates missing sources and builds before opening the editor. Typst uses
the native watcher’s first result for this build, then keeps that watcher running.

## Preview

fancy-cat opens right of the editor in tmux or Ghostty; otherwise Zathura, then
Sioyek (`HXP_NO_SPLIT=1` forces these). Native X11 Ghostty splits with
`Ctrl+Shift+O`, needs exactly two splits sourcing hxp, and this binding:

```text
keybind = ctrl+shift+h=goto_split:left
```

Floating X11 windows are placed with `wmctrl`/`xprop`; Wayland placement is manual.

Closing the editor or terminal stops the watcher and removes scratch files,
keeping the PDF; detaching tmux does not. Typst watches incrementally; other
builds use watchexec or inotifywait, and saves during a build queue a rebuild.
PDFs are replaced atomically and fancy-cat is told to reload.

## Inverse search (PDF → editor)

| Viewer | Trigger |
|---|---|
| fancy-cat | Ctrl+L at pointer/view centre; Ctrl+click |
| Sioyek | `F5` at pointer, or Ctrl+click |
| Zathura | Ctrl+click |

Requires `hxp-jump`, `hxp-inverse`, and Python 3 on `PATH`. fancy-cat Ctrl+L and
Typst lookup need the fork's `--inverse-search-resolver` (`inverse_search`
action, default `<C-l>`).

LaTeX uses SyncTeX; Markdown also needs latexmk and maps approximately. Typst
matches prose in the root and its literal local includes, skipping code, math,
strings, and raw text. Failures report `AmbiguousSourceText`,
`NoMatchingSourceText`, or `NoSyncTeXSourceLocation`.

tmux Ctrl+click needs this binding (`tmux source-file ~/.tmux.conf`):

```tmux
bind -n C-MouseDown1Pane if -F -t = '#{mouse_any_flag}' { send-keys -M } { swap-pane -s @ }
```

GUI viewers spawn an editor only when the helper has a terminal; otherwise X11
uses `xdotool`.

## Forward search (editor → PDF)

Helix, `~/.config/helix/config.toml`:

```toml
[keys.normal]
"C-l" = ":sh ~/.local/bin/hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}"
```

Micro, `~/.config/micro/bindings.json` (goto stays at `Ctrl-e goto`):

```json
"Ctrl-l": "command:hxpfwd"
```

`hxp-fwd FILE LINE [COL]` targets the session preview. Markdown maps through
generated TeX; Typst matches cached `pdftotext` output. Zathura needs `gdbus`.
Math and generated text may not match.

## Viewer keybindings

Sioyek adds `F5` inverse search, `i` dark colors, `a` fit width, `Ctrl-d/u`
half-pages, `J/K` next/previous page, `H/L` page top/bottom, `'` mark, and
`Ctrl-l` reload. Zathura keeps stock bindings.

Optional Sioyek dual panel: uncomment `_dual_panelify d` in
`config/sioyek/keys_user.config` and create the venv (`HXP_SIOYEK_VENV`
overrides it):

```sh
venv="${XDG_DATA_HOME:-$HOME/.local/share}/sioyek-extensions"
python3 -m venv "$venv" && "$venv/bin/python" -m pip install sioyek
```

## Builds

| Source | Build | Root |
|---|---|---|
| `.md` | Pandoc → latexmk; direct Pandoc without latexmk (no SyncTeX) | Opened file |
| `.tex` | `latexmk -pdf -synctex=1` | Opened `\documentclass` source, or nearest `main.tex`, `root.tex`, `thesis.tex` containing it |
| `.typ` | `typst watch` | Nearest `main.typ`; `typst.toml` stops the search |

PDFs are written beside the root. LaTeX uses pdflatex unless `latexmkrc` says
otherwise; a sibling bibliography enables `-bibtex`.

Markdown prefers xelatex, then lualatex, then pdflatex, and accepts `\(…\)`/`\[…\]`
math. Frontmatter `bibliography:` replaces the first sibling `.bib`; `geometry:`
replaces `HXP_MD_MARGIN`. A CJK font is loaded when the source or a bibliography
contains Han, kana, or Hangul; `HXP_CJK_FONT` or `CJKmainfont:` picks it.

## Errors

Helix: `:open %sh{hxp-first-error}`. Micro: `Ctrl-e hxperror`.

A failed build replaces the preview with an error PDF (message, location,
context, log). With `--keep-last-good`, a good PDF stays and only diagnostics
update.

## Environment variables

| Variable | Effect |
|---|---|
| `HXP_EDITOR` | `helix` (default) or `micro` |
| `HXP_VIEWER` | GUI preference: `zathura` or `sioyek` |
| `HXP_CJK_FONT` | Markdown CJK font |
| `HXP_MD_MARGIN` | Geometry; default `0.75in`, empty for class default |
| `HXP_NO_SPLIT=1` | Use a GUI viewer |
| `HXP_KEEP_LAST_GOOD=1` | Same as `--keep-last-good` |
| `HXP_NO_NATIVE_TYP=1` | Full Typst rebuilds |
| `HXP_NO_WATCHEXEC=1` | Use inotifywait |
| `HXP_NO_TILE=1` | Disable GUI placement |
| `HXP_WM` | Force `tiling` or `floating` |
| `HXP_SIOYEK_VENV` | Sioyek extensions venv |
| `HXP_AWK` | Awk binary |

## Runtime files

`<runtime>` is `${XDG_RUNTIME_DIR:-/tmp}/hxp`; `<sha1>` hashes the source path.
Crash leftovers may be deleted.

| Path | Purpose |
|---|---|
| `<root-stem>.pdf` | Output |
| `<src-dir>/.<stem>.error.{log,md}`, `.debug.tex`, `.tmp*.pdf` | Diagnostics, staging |
| `<src-dir>/.hxp_build_<stem>/` | latexmk output |
| `<pdf-dir>/<root-stem>.synctex.gz` | Search data |
| `<runtime>/<sha1>.{state,state.buf,errpdf,pdftext}` | Session state, caches |
| `<runtime>/fonts/`, `errdoc.*/`, `viewer-launch.lock` | Error pages, launch lock |

## tmux restore

`hxp-sessions` prints `TMUX_SOCKET TMUX_PANE EDITOR VIEWER VIEWER_SOCKET SOURCE`
as TSV. The tmux-resurrect save hook stores fancy-cat panes as
`hxp-resume PANE_INDEX EDITOR SOURCE`; add `hxp-resume` to
`@resurrect-processes`. After restore it restarts hxp in the idle editor pane.

## Troubleshooting

Start with `hxp --doctor`.

| Problem | Check |
|---|---|
| No updates | Try `HXP_NO_WATCHEXEC=1` |
| Wrong or new editor | Use tmux or install `xdotool`; check helper `PATH` |
| fancy-cat Ctrl+L fails | Update the fork; restart hxp |
| `NoLiveSourceSession` | Restart hxp |
| `AmbiguousSourceText` | Search more distinctive prose |
| Ghostty types into preview | Add the left-focus binding; keep two splits |
| Unknown Micro `hxpfwd` | Rerun the installer |
| Sioyek reuses a window | Remove single-window overrides |
| Missing CJK | Install `fonts-noto-cjk` and `texlive-lang-cjk`, or set `HXP_CJK_FONT` |
| Micro jump inserts commands | Undo; bind `Ctrl-e` to `CommandMode` |

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

`zsh/hxp-main.zsh` owns sessions, `zsh/hxp-lib.zsh` builds and errors, `bin/`
search and restore.

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
