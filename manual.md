# hxp manual

Live PDF preview for Markdown, LaTeX, and Typst, using Helix or Micro with
fancy-cat. Saves rebuild the PDF and compile failures appear as error PDFs.

## Setup

Follow the [installation steps](README.md#install). The installer links the shell
functions, helpers, viewer configs, and Micro plugin; `--no-config` skips the
Zathura and Sioyek configs for dotfiles that own them. Rerunning it after an
update creates missing links, including `~/.local/bin/hxp-first-error` and
`~/.config/micro/plug/hxpfwd`. The chezmoi-managed editor configs supply the
F8 bindings. The installer backs up existing regular files
as `*.bak.<timestamp>`. Run `./install.sh --deps` for dependencies or
`hxp --doctor` to check your setup.

## Commands

```sh
hxp notes.md                 # Helix, viewer, and watcher
hxp --keep-last-good notes.md # keep the PDF on a failed build
hxp --micro paper.tex        # Micro instead of Helix
hxp --helix slides.typ       # override HXP_EDITOR
wpdf [-q] [--no-initial] FILE # watcher only
hxp_errs FILE                # live error readout; pair with hxp or wpdf
hxp --doctor
```

All three file commands accept `.md`, `.tex`, and `.typ`. `hxp` creates a starter
file when needed, compiles it, and opens the editor and preview. An initial
failure also opens diagnostic buffers. `wpdf -q` suppresses status messages;
`--no-initial` skips the first build.

fancy-cat opens to the right. In tmux, the editor pane keeps focus. Native X11
Ghostty uses `xdotool` to press `Ctrl+Shift+O` (Ghostty's default
`new_split:right`) and `Ctrl+Shift+H` to refocus the editor. `Ctrl+Shift+H` is
not a Ghostty default; add it to `~/.config/ghostty/config`:

```
keybind = ctrl+shift+h=goto_split:left
```

Keep the editor and its preview as the window’s only splits. hxp can confirm
that the Ghostty window has focus, but not which split, so inverse-search
keystrokes go to whichever split is left of the preview. The split’s zsh must
source hxp at startup.

If the preview cannot open there, hxp closes the unused split and tries Zathura,
then Sioyek. Set `HXP_NO_SPLIT=1` to always use those. `hxp --doctor` reports
why a split is unavailable.

Quitting the editor stops the watcher, removes scratch files, and keeps the PDF.
hxp closes its preview. Shared Sioyek windows stay open if ownership is unclear.

Watchers track project sources and bibliographies. Typst uses incremental
`typst watch`; other paths prefer `watchexec` with a 250ms debounce, then fall
back to `inotifywait`. Generated files are excluded to prevent rebuild loops.

## Inverse search (PDF → editor)

| Viewer | Trigger |
|---|---|
| fancy-cat | Ctrl+click typeset text with a SyncTeX sidecar |
| Sioyek | Hover text and press `F5`, or `Ctrl`+click |
| Zathura | `Ctrl`+click text |

Keep `hxp-jump` on `PATH`. It targets the editor pane in tmux, uses `xdotool`
on X11, or opens a new editor. LaTeX uses SyncTeX directly. Markdown needs
`latexmk` for approximate source mapping. Typst supports forward search only.

For a separate error pane:

```sh
tmux new-session \; \
  send-keys 'hxp paper.tex' C-m \; \
  split-window -h \; \
  send-keys 'hxp_errs paper.tex' C-m \; \
  select-pane -L
```

## Forward search (editor → PDF)

Helix — add to `~/.config/helix/config.toml`:

```toml
[keys.normal]
"C-l" = ":sh ~/.local/bin/hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}"
```

Micro — add to `~/.config/micro/bindings.json`:

```json
"Ctrl-l": "command:hxpfwd"
```

The installed `hxpfwd` plugin runs searches asynchronously. This replaces Micro's
`Ctrl-l` goto prompt, which remains available through `Ctrl-e goto`.

`hxp-fwd FILE LINE [COL]` targets the session’s fancy-cat socket, Zathura
process, or Sioyek window. LaTeX uses SyncTeX. Markdown first maps the cursor
to generated TeX.

### Typst text search

hxp uses `pdftotext` to find pages matching the cursor’s text. Nearby source
lines break ties, with closer lines weighted more heavily.
fancy-cat and Sioyek highlight the match. Zathura jumps to the page via
`gdbus`. Tied scores select the earliest page. Math and generated text
can yield no match.

## Viewer keybindings

Sioyek keeps its default bindings and adds:

| Key | Action |
|---|---|
| `F5` | Inverse search at the mouse cursor |
| `i` | Toggle dark colors |
| `a` | Fit page width |
| `Ctrl-d` / `Ctrl-u` | Half-page down / up |
| `Shift-J` / `Shift-K` | Next / previous page |
| `H` / `L` | Top / bottom of page |
| `'` | Go to mark |
| `Ctrl-l` | Reload |

Zathura keeps stock bindings. Its config enables clipboard selection, SyncTeX,
incremental search, and fit-to-width, with the status bar hidden. Both viewers
reload automatically. Each hxp session opens its own preview window.

Optional Sioyek dual-panel extension:

```sh
venv="${XDG_DATA_HOME:-$HOME/.local/share}/sioyek-extensions"
python3 -m venv "$venv"
"$venv/bin/python" -m pip install sioyek
```

Uncomment `_dual_panelify d` in `config/sioyek/keys_user.config` to bind `d`.
Set `HXP_SIOYEK_VENV` to use another venv.

## Per-language behavior

| Source | Build | Project root |
|---|---|---|
| `.md` | Pandoc → LaTeX → latexmk; direct Pandoc fallback without SyncTeX | Opened file |
| `.tex` | `latexmk -pdf -synctex=1` | Opened file if it contains `\documentclass`; otherwise nearest `main.tex`, `root.tex`, or `thesis.tex` containing it |
| `.typ` | `typst watch`, or `typst compile` when native watch is disabled | Nearest `main.typ`; `typst.toml` stops the upward search |

The PDF lives beside the root source. LaTeX builds run from its directory so
relative inputs resolve. Typst uses that directory as `--root`. PDFs are
published atomically so existing readers retain a stable copy during builds.

### Markdown

- Supports `\(…\)` and `\[…\]` math; links are blue.
- Uses xelatex, then lualatex, then pdflatex when available.
- YAML `bibliography:` takes precedence; otherwise the first sibling `.bib`
  is loaded automatically with citeproc.
- Margins default to `0.75in`. `HXP_MD_MARGIN=2cm` sets all sides;
  `HXP_MD_MARGIN="top=2cm,left=3cm"` sets geometry options. An empty value keeps
  class defaults. Frontmatter `geometry:` overrides the environment.
- CJK fonts are detected automatically. Override with `HXP_CJK_FONT` or
  frontmatter `CJKmainfont:`.

### LaTeX and Typst

LaTeX uses pdflatex by default; configure other engines through `latexmkrc`.
A sibling bibliography enables `-bibtex`. Included sources, `.bib`, `.sty`,
and `.cls` changes trigger project rebuilds.

Typst watches imported sources natively and renders error PDFs without LaTeX.
Set `HXP_NO_NATIVE_TYP=1` for the generic full-rebuild loop.

## Error reporting

Bind `F8` to `:open %sh{hxp-first-error}` in Helix normal mode or
`command:hxperror` in Micro to jump to the first reported source location.
Markdown locations are approximate. If an error cannot be mapped to a Markdown
line, F8 opens the Markdown file without moving the cursor. A compiler error
without a source location has no jump target.

Use `--keep-last-good` with `hxp` or `wpdf` to keep the last good PDF on
failure. Diagnostics still appear in `hxp_errs`. Until a build succeeds, the
preview shows an error PDF for the latest failure.

By default, a failed build replaces the preview with an error PDF showing the primary
message, source location, nearby text, and compiler extract. Markdown includes
TeX context and an estimated Markdown location. `hxp_errs` displays the same
status in a terminal pane, including a command to open the error location.

## Environment variables

| Variable | Effect |
|---|---|
| `HXP_EDITOR` | `helix` (default) or `micro`; other values fall back to Helix |
| `HXP_VIEWER` | GUI fallback preference (`zathura` or `sioyek`) |
| `HXP_CJK_FONT` | Markdown CJK font family |
| `HXP_MD_MARGIN` | Markdown geometry; default `0.75in` |
| `HXP_NO_SPLIT=1` | Skip the fancy-cat split; use Zathura or Sioyek |
| `HXP_KEEP_LAST_GOOD=1` | Enable `--keep-last-good` by default |
| `HXP_NO_NATIVE_TYP=1` | Disable native Typst watch |
| `HXP_NO_WATCHEXEC=1` | Use the inotify fallback |
| `HXP_NO_TILE=1` | Disable GUI window placement |
| `HXP_WM` | Force `tiling` or `floating` |
| `HXP_SIOYEK_VENV` | Sioyek extensions venv |
| `HXP_AWK` | Override the awk binary |

## GUI fallback windows

On floating X11 desktops, `wmctrl` and `xprop` place the editor left and preview
right. Tiling WMs handle placement themselves. On Wayland or without these
tools, place windows manually; tmux inverse search still works.

## Runtime & output files

| Path | Purpose |
|---|---|
| `<root-stem>.pdf` | Output; kept after exit |
| `<src-dir>/.<stem>.error.log`, `.error.md` | Compiler log and error document |
| `<src-dir>/.<stem>.debug.tex` | Markdown diagnostic intermediate |
| `<src-dir>/.<stem>.tmp.pdf`, `.tmp.watch.pdf` | Atomic publication and native Typst staging |
| `<src-dir>/.hxp_build_<stem>/` | latexmk output and Markdown `.hxp.tex` |
| `<pdf-dir>/<root-stem>.synctex.gz` | Search data; removed on exit |
| `${XDG_RUNTIME_DIR:-/tmp}/hxp/<sha1>.state` | Source, PDF, editor/viewer, pane/window IDs, and PIDs |
| `<state>.buf` | Micro's last inverse-search buffer |
| `${XDG_RUNTIME_DIR:-/tmp}/hxp/<sha1>.errpdf` | Marks a PDF that is currently an error page |
| `<runtime>/hxp/viewer-launch.lock` | Persistent shared startup lock |

Scratch files left after a crash can be deleted; the next session recreates them.

## tmux restore

`hxp-sessions` lists live sessions, one per line, tab-separated:
`TMUX_SOCKET TMUX_PANE EDITOR VIEWER VIEWER_SOCKET SOURCE`. A tmux-resurrect
save hook saves each session's editor pane as a shell and its fancy-cat pane as
`hxp-resume PANE_INDEX EDITOR SOURCE`; add `hxp-resume` to `@resurrect-processes`.
On restore it waits while the server option `@resurrect-restoring` is 1 and for
a Ghostty client, then restarts the editor pane running hxp once its shell is
idle. While it waits, its pane option `@hxp-resume` holds
`EDITOR_PANE_ID EDITOR SOURCE`, so a save can write the editor's current index.

## Troubleshooting

Start with `hxp --doctor`.

| Problem | Check |
|---|---|
| Preview does not update | Install watch tools; try `HXP_NO_WATCHEXEC=1` |
| Inverse search opens another editor | Launch inside tmux, or install `xdotool`; check helpers on `PATH` |
| Ghostty inverse search types into the preview | Bind `ctrl+shift+h=goto_split:left`; keep only the editor and preview splits |
| Markdown search fails | Install `latexmk`; Markdown needs generated SyncTeX data |
| Typst search is inaccurate | Text matching is approximate; install `pdftotext` and, for Zathura, `gdbus` |
| CJK text is missing | Install `fonts-noto-cjk` or set `HXP_CJK_FONT` |
| Micro reports unknown `hxpfwd` | Re-run `install.sh` and add the keybinding |
| A Micro jump types commands into the document | Undo and check that `Ctrl-e` is bound to `CommandMode` |
| Search selects another Zathura window | Restart hxp from a new shell after updating |
| Sioyek reuses another session's window | Remove custom single-window overrides |

## Development

```sh
zsh test/parse-test.zsh
zsh test/workflow-test.zsh
zsh test/smoke.zsh
bash test/sessions-test.sh
bash test/resume-test.sh   # needs tmux
```

Parser, workflow, and session tests need no compilers or GUI. Smoke tests
compile each available language and exercise native Typst watch. CI runs them all.

`zsh/hxp-main.zsh` owns sessions and windows; `zsh/hxp-lib.zsh` handles builds,
errors, and diagnostics. `bin/hxp-compile` serves the watcher; `hxp-jump` and
`hxp-fwd` handle search, using `hxp-mdline`, `hxp-texline`, and `hxp-typtext`.
`hxp-sessions` and `hxp-resume` serve tmux restore. Micro's adapter is in
`config/micro/plug/hxpfwd/`.

## Uninstall

Remove the installed symlinks and the source line from `~/.zshrc`:

```sh
rm -f ~/.zsh/hxp-main.zsh ~/.zsh/hxp-lib.zsh \
      ~/.local/bin/hxp-compile ~/.local/bin/hxp-first-error ~/.local/bin/hxp-jump \
      ~/.local/bin/hxp-mdline ~/.local/bin/hxp-fwd \
      ~/.local/bin/hxp-texline ~/.local/bin/hxp-typtext \
      ~/.local/bin/hxp-dual-panelify ~/.local/bin/hxp-sessions ~/.local/bin/hxp-resume \
      ~/.config/zathura/zathurarc \
      ~/.config/sioyek/prefs_user.config ~/.config/sioyek/keys_user.config \
      ~/.config/micro/plug/hxpfwd
```

Restore any installer backups you want to keep.
