# hxp

Live-preview workflow for Markdown / LaTeX / Typst, glued together from
[helix], [pandoc], [latexmk], [typst], and [zathura] or [sioyek]. Edit on
the left, compiled PDF auto-reloads on the right, errors render into the
PDF (or into a side terminal pane) so you can fix and re-save without
leaving the editor.

[helix]:   https://helix-editor.com
[pandoc]:  https://pandoc.org
[latexmk]: https://www.cantab.net/users/johncollins/latexmk/
[typst]:   https://typst.app
[zathura]: https://pwmt.org/projects/zathura/
[sioyek]:  https://sioyek.info

## What you get

- `hxp <file.{md,tex,typ}>` &mdash; tile helix on the left, the PDF viewer
  on the right, recompile on save. Auto-scaffolds the file if it doesn't
  exist yet.
- `wpdf <file>` &mdash; just the watcher half: recompile on save without
  launching helix or the viewer.
- `hxp_errs <file>` &mdash; live terminal display of the latest compile
  state (OK / first error + suspect line + helix-jump target). Run in a
  separate tmux pane next to `hxp` if you want errors in your eyeline
  instead of glancing at the PDF.
- Synctex reverse-search: Ctrl+click in the PDF jumps to the source line
  in your already-running helix instance (when you launched `hxp` inside
  tmux). Falls back to spawning a fresh `hx` if no live pane is reachable.
- CJK font auto-selection for Markdown PDFs (Korean / Japanese / Chinese
  glyphs render instead of disappearing). Override via `HXP_CJK_FONT`.
- Multi-error reporting: typst halts at the first error by default, but
  pandoc/latex cascading errors get a windowed extract with an
  approximate count in the error PDF header.

## Install

```sh
git clone https://github.com/<you>/hxp.git ~/Applications/hxp
~/Applications/hxp/install.sh
```

Then add this single line to `~/.zshrc`:

```zsh
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"
```

`install.sh` symlinks files from the repo into:

| Repo path | Linked to |
|---|---|
| `zsh/hxp-main.zsh` | `~/.zsh/hxp-main.zsh` |
| `zsh/hxp-lib.zsh` | `~/.zsh/hxp-lib.zsh` |
| `bin/hxp-compile` | `~/.local/bin/hxp-compile` |
| `bin/hxp-jump` | `~/.local/bin/hxp-jump` |
| `config/zathura/zathurarc` | `~/.config/zathura/zathurarc` |
| `config/sioyek/prefs_user.config` | `~/.config/sioyek/prefs_user.config` |

Existing files (not symlinks) are backed up to `*.bak.<timestamp>` before
linking. Re-running the script is safe.

## Dependencies

| Required | Recommended |
|---|---|
| zsh, helix, pandoc, inotify-tools | watchexec, xelatex, latexmk, typst, wmctrl, xprop, sioyek **or** zathura |

For CJK markdown PDFs install `fonts-noto-cjk` (Debian/Ubuntu) or set
`HXP_CJK_FONT="Your Font"` if you want a different family.

## Display server

The window-tiling features (`wmctrl`, `xprop`) require **X11** — any
EWMH-compliant X11 window manager works (GNOME-on-X11, KDE Plasma X11,
XFCE, i3, openbox, dwm, …). Wayland is not supported; external tools
can't move windows there by design.

On Wayland (or a system without `wmctrl`/`xprop` installed) the tiling
code silently no-ops via `command -v` guards — `hxp` itself still works:
the viewer launches, the watcher recompiles, error PDFs render, synctex
reverse-search works. You just lose the automatic split-screen layout.
Set `HXP_NO_TILE=1` to skip the tiling code paths explicitly.

Check which session you're in:

```sh
echo "$XDG_SESSION_TYPE"   # x11 or wayland
```

## Knobs

| Env var | Effect |
|---|---|
| `HXP_VIEWER` | Force `sioyek` or `zathura` instead of auto-detect. |
| `HXP_CJK_FONT` | Override the CJK font for markdown PDFs. |
| `HXP_NO_NATIVE_TYP=1` | Use the generic compile loop instead of `typst watch`. |
| `HXP_NO_WATCHEXEC=1` | Fall back to `inotifywait` instead of `watchexec`. |
| `HXP_NO_TILE=1` | Disable wmctrl tiling of editor / viewer windows. |

## Layout

```
hxp/
├── README.md
├── install.sh
├── zsh/
│   ├── hxp-main.zsh   # hxp() / wpdf() / tiling helpers
│   └── hxp-lib.zsh    # _hxp_compile_once / error rendering / hxp_errs
├── bin/
│   ├── hxp-compile    # watchexec-driven recompile wrapper
│   └── hxp-jump       # synctex reverse-search shim
└── config/
    ├── zathura/zathurarc
    └── sioyek/prefs_user.config
```

`hxp-main.zsh` sources `hxp-lib.zsh`. The compile helpers in `hxp-lib.zsh`
are kept separate so `hxp-compile` (invoked per save by watchexec) can
load them without paying the cost of sourcing the rest of `.zshrc`.

## Runtime files

The session creates these next to your source file; all are swept on
`hxp` exit, except the rendered PDF which is kept:

| Path | Role |
|---|---|
| `<src-dir>/.<stem>.error.log` | Raw compiler stderr/stdout. |
| `<src-dir>/.<stem>.error.md` | Markdown rendered into the error PDF. |
| `<src-dir>/.<stem>.debug.tex` | Pandoc's md→latex output (md path, on failure). |
| `<src-dir>/.<stem>.tmp.pdf` | Stage path before atomic move to the real PDF. |
| `<src-dir>/.hxp_build_<stem>/` | latexmk's build tree (tex only). |
| `<pdf-dir>/<stem>.synctex.gz` | Synctex sidecar (tex only, while viewing). |
| `${XDG_RUNTIME_DIR:-/tmp}/hxp/<sha1>.state` | hxp-jump's per-source state file. |
