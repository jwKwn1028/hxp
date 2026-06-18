# hxp

- Mostly for personal use

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
- Synctex inverse search: hover over text in the PDF and press **F5** to
  jump to the source line in your already-running helix instance (when you
  launched `hxp` inside tmux). Works for `.tex` and `.md` files —
  markdown goes through a two-step pipeline (pandoc md→tex, latexmk
  tex→pdf) so the synctex data persists and `hxp-jump` maps it back to
  the original markdown line. Falls back to spawning a fresh `hx` if no
  live pane is reachable.
- CJK font auto-selection for Markdown PDFs (Korean / Japanese / Chinese
  glyphs render instead of disappearing). Override via `HXP_CJK_FONT`.
- Multi-error reporting: typst halts at the first error by default, but
  pandoc/latex cascading errors get a windowed extract with an
  approximate count in the error PDF header.
- Uniform error surfacing across all three languages: a failed compile
  renders an error PDF and flips `hxp_errs` to ERROR. This now includes
  the default `typst watch` path (previously typst errors were silent —
  the viewer kept showing the last good PDF). Typst error PDFs are rendered
  with typst itself, so `.typ` users don't need a LaTeX toolchain.
- `hxp --doctor` &mdash; one screen showing which tools are detected and,
  for each missing one, the feature it disables. Run it first when
  something isn't behaving.

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
| `bin/hxp-mdline` | `~/.local/bin/hxp-mdline` |
| `bin/hxp-dual-panelify` | `~/.local/bin/hxp-dual-panelify` |
| `config/zathura/zathurarc` | `~/.config/zathura/zathurarc` |
| `config/sioyek/prefs_user.config` | `~/.config/sioyek/prefs_user.config` |
| `config/sioyek/keys_user.config` | `~/.config/sioyek/keys_user.config` |

Existing files (not symlinks) are backed up to `*.bak.<timestamp>` before
linking. Re-running the script is safe.

## Dependencies

The canonical list lives in `install.sh`. Print it without installing:

```sh
./install.sh --deps
```

In short: `zsh`, `helix`, `pandoc`, and `inotify-tools` are required;
`watchexec`, `xelatex`, `latexmk`, `typst`, `wmctrl`, `xprop`, and
`sioyek` or `zathura` are recommended; `tmux` / `xdotool` make PDF→editor
inverse search land in your running helix. For CJK markdown PDFs install
`fonts-noto-cjk` (Debian/Ubuntu) or set `HXP_CJK_FONT="Your Font"`.

Any `awk` works (gawk, mawk, busybox) — no gawk-only features are used.
After installing, run `hxp --doctor` to see which features are active and
what each missing tool would enable.

## Display server

The window-tiling features (`wmctrl`, `xprop`) require **X11**. Wayland
is not supported; external tools can't move windows there by design.

On Wayland (or a system without `wmctrl`/`xprop` installed) the tiling
code silently no-ops via `command -v` guards — `hxp` itself still works:
the viewer launches, the watcher recompiles, error PDFs render, synctex
reverse-search works. You just lose the automatic split-screen layout.
Set `HXP_NO_TILE=1` to skip the tiling code paths explicitly.

Check which session you're in:

```sh
echo "$XDG_SESSION_TYPE"   # x11 or wayland
```

### Floating vs. tiling window managers

`hxp` detects the WM kind at runtime via `wmctrl -m` (falls back to
`_NET_WM_NAME` on the root window) and picks one of two strategies:

- **Floating WMs** (XFCE/xfwm, GNOME-on-X11/mutter, KDE/kwin, openbox,
  …): `hxp` uses `wmctrl -e` to place helix on the left half and the
  viewer on the right half of the active monitor's work area.
- **Tiling WMs** (i3, sway, bspwm, dwm, awesome, xmonad, qtile,
  herbstluftwm, river, hyprland): the geometry calls are skipped —
  `_NET_MOVERESIZE_WINDOW` is ignored for managed containers anyway, so
  fighting the WM is pointless. The viewer launches while the helix
  terminal is focused, and the WM's own tiling logic (e.g.
  [autotiling][autotiling] on i3) places it as a sibling split.

[autotiling]: https://github.com/nwg-piotr/autotiling

Override the detection with `HXP_WM=tiling` or `HXP_WM=floating` if the
heuristic guesses wrong on your setup.

## Knobs

| Env var | Effect |
|---|---|
| `HXP_VIEWER` | Force `sioyek` or `zathura` instead of auto-detect. |
| `HXP_CJK_FONT` | Override the CJK font for markdown PDFs. |
| `HXP_NO_NATIVE_TYP=1` | Use the generic compile loop instead of `typst watch` (full recompiles; same error surfacing). |
| `HXP_NO_WATCHEXEC=1` | Fall back to `inotifywait` instead of `watchexec`. |
| `HXP_NO_TILE=1` | Disable wmctrl tiling of editor / viewer windows. |
| `HXP_WM` | Force `tiling` or `floating` instead of auto-detect (see Display server). |
| `HXP_SIOYEK_VENV` | Path to the sioyek-python-extensions venv (default `${XDG_DATA_HOME:-~/.local/share}/sioyek-extensions`). |
| `HXP_AWK` | Force a specific awk binary for log parsing (mainly for the tests). |

## Layout

```
hxp/
├── README.md
├── install.sh
├── zsh/
│   ├── hxp-main.zsh   # hxp() / wpdf() / tiling helpers
│   └── hxp-lib.zsh    # _hxp_compile_once / error rendering / hxp_errs
├── bin/
│   ├── hxp-compile        # watchexec-driven recompile wrapper
│   ├── hxp-jump           # synctex inverse-search shim
│   ├── hxp-mdline         # shared md<-tex line-mapping heuristic
│   └── hxp-dual-panelify  # sioyek dual-panel wrapper (PATH-resolved)
├── config/
│   ├── zathura/zathurarc
│   └── sioyek/
│       ├── prefs_user.config
│       └── keys_user.config
└── test/
    ├── parse-test.zsh     # toolchain-free compiler-log parser tests
    └── smoke.zsh          # per-language compile + typst-watch tests
```

`hxp-main.zsh` sources `hxp-lib.zsh`. The compile helpers in `hxp-lib.zsh`
are kept separate so `hxp-compile` (invoked per save by watchexec) can
load them without paying the cost of sourcing the rest of `.zshrc`.

## Tests

```sh
zsh test/parse-test.zsh   # compiler-log parsers, run under every awk present
zsh test/smoke.zsh        # good/bad compile per language (+ typst watch loop)
```

`parse-test.zsh` needs no compilers (the fast gate; it also runs in CI under
both gawk and mawk to keep the log parsers POSIX-awk clean). `smoke.zsh`
exercises the real pipeline and **skips** any language whose tools aren't
installed, so it's useful with a partial toolchain too. Both run on every
push via `.github/workflows/ci.yml`.

## Runtime files

The session creates these next to your source file; all are swept on
`hxp` exit, except the rendered PDF which is kept:

| Path | Role |
|---|---|
| `<src-dir>/.<stem>.error.log` | Raw compiler stderr/stdout. |
| `<src-dir>/.<stem>.error.md` | Markdown rendered into the error PDF. |
| `<src-dir>/.<stem>.debug.tex` | Pandoc's md→latex output (md path, fallback on failure). |
| `<src-dir>/.<stem>.tmp.pdf` | Stage path before atomic move to the real PDF. |
| `<src-dir>/.hxp_build_<stem>/` | latexmk's build tree (tex; md with synctex intermediate). |
| `<pdf-dir>/<stem>.synctex.gz` | Synctex sidecar (tex and md, while viewing). |
| `${XDG_RUNTIME_DIR:-/tmp}/hxp/<sha1>.state` | hxp-jump's per-source state file. |
