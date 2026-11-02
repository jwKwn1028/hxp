# hxp manual

Live PDF preview for Markdown, LaTeX, and Typst, using Helix or Micro with
Sioyek or Zathura. Saves rebuild the PDF; compile failures appear as error PDFs.

## Setup

Follow [README.md](README.md) to install. `./install.sh --deps` lists dependencies;
`hxp --doctor` checks installed tools and available features.

Add to `~/.zshrc`, put `~/.local/bin` on `PATH`, and reload the shell:

```zsh
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"
```

The installer links shell functions, helpers, viewer configs, and Micro's plugin.
Existing files are backed up as `*.bak.<timestamp>`. Only your chosen editor is
required; forward-search keybindings must be added separately.

## Commands

```sh
hxp notes.md                 # Helix, viewer, and watcher
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

Quitting the editor stops the watcher and removes scratch files, keeping the PDF.
Cleanup closes the owned viewer window; an unidentified Sioyek window stays open
because its process may serve other sessions. Zathura has a dedicated process.

Watchers track project sources and bibliographies. Typst uses incremental
`typst watch`; other paths prefer `watchexec` with a 250ms debounce, then fall
back to `inotifywait`. Generated files are excluded to prevent rebuild loops.

## Inverse search (PDF → editor)

| Viewer | Trigger |
|---|---|
| Sioyek | Hover text and press `F5`, or `Ctrl`+click |
| Zathura | `Ctrl`+click text |

Run hxp inside **tmux** for jumps into the existing editor pane. Outside tmux,
`hxp-jump` uses `xdotool` on X11, then falls back to a new editor. Helpers must
be on `PATH` before the viewer starts.

LaTeX uses SyncTeX directly. Markdown requires `latexmk` and maps generated TeX
positions back to Markdown approximately. Typst has no inverse search.

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

`hxp-fwd FILE LINE [COL]` uses session state to find the PDF and owned viewer.
LaTeX searches use SyncTeX; Markdown first maps the cursor onto generated TeX.
Zathura searches target the recorded process, including when another window
shows the same PDF. Sioyek reuses a window only after focusing the owned one.

### The typst fallback

Typst forward search finds the cursor line's prose in text extracted by
`pdftotext`. Sioyek highlights the match; Zathura uses D-Bus to change pages
and requires `gdbus`.

This is approximate: repeated text selects its first occurrence, and generated
text or math may not match. Without usable text, or an available Markdown
mapping, forward search only raises the viewer.

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

A failed build replaces the preview with an error PDF showing the primary
message, source location, nearby text, and compiler extract. Markdown includes
TeX context and an estimated Markdown location. `hxp_errs` displays the same
status in a terminal pane, including a command to open the error location.

## Environment variables

| Variable | Effect |
|---|---|
| `HXP_EDITOR` | `helix` (default) or `micro`; other values fall back to Helix |
| `HXP_VIEWER` | Force `sioyek` or `zathura`; otherwise prefer Sioyek |
| `HXP_CJK_FONT` | Markdown CJK font family |
| `HXP_MD_MARGIN` | Markdown geometry; default `0.75in` |
| `HXP_NO_NATIVE_TYP=1` | Disable native Typst watch |
| `HXP_NO_WATCHEXEC=1` | Use the inotify fallback |
| `HXP_NO_TILE=1` | Disable window placement |
| `HXP_WM` | Force `tiling` or `floating` |
| `HXP_SIOYEK_VENV` | Sioyek extensions venv |
| `HXP_AWK` | Override the awk binary |

Example: `HXP_VIEWER=zathura hxp notes.md`. Internal viewer PID/kind variables
are set by hxp.

## Window tiling

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
| `<runtime>/hxp/viewer-launch.lock` | Persistent shared startup lock |

Scratch files left after a crash can be deleted; the next session recreates them.

## Troubleshooting

Start with `hxp --doctor`.

| Problem | Check |
|---|---|
| Preview does not update | Install watch tools; try `HXP_NO_WATCHEXEC=1` |
| Inverse search opens another editor | Launch inside tmux, or install `xdotool`; check helpers on `PATH` |
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
```

Parser and workflow tests need no compilers or GUI. Smoke tests compile each
available language and exercise native Typst watch. CI runs all three.

`zsh/hxp-main.zsh` owns sessions and windows; `zsh/hxp-lib.zsh` handles builds,
errors, and diagnostics. `bin/hxp-compile` serves the watcher; `hxp-jump` and
`hxp-fwd` handle search, using `hxp-mdline`, `hxp-texline`, and `hxp-typtext`.
Micro's adapter is in `config/micro/plug/hxpfwd/`.

## Uninstall

Remove the installed symlinks and the source line from `~/.zshrc`:

```sh
rm -f ~/.zsh/hxp-main.zsh ~/.zsh/hxp-lib.zsh \
      ~/.local/bin/hxp-compile ~/.local/bin/hxp-jump \
      ~/.local/bin/hxp-mdline ~/.local/bin/hxp-fwd \
      ~/.local/bin/hxp-texline ~/.local/bin/hxp-typtext \
      ~/.local/bin/hxp-dual-panelify \
      ~/.config/zathura/zathurarc \
      ~/.config/sioyek/prefs_user.config ~/.config/sioyek/keys_user.config \
      ~/.config/micro/plug/hxpfwd
```

Restore any installer backups you want to keep.
