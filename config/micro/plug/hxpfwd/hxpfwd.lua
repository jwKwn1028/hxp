VERSION = "1.0.0"

-- hxp forward search for micro: move the PDF to the line under the cursor.
--
-- helix can hand a shell command its cursor position directly
-- (`:sh hxp-fwd '%{buffer_name}' %{cursor_line} %{cursor_column}`); micro's
-- keybindings interpolate nothing, so the call has to originate inside a
-- plugin. All this does is find the position and shell out to hxp-fwd, which
-- is the same shim helix uses — the viewer/synctex work all lives there.
--
-- hxp ships the command, not the binding (same as it does for helix). Add one
-- line to ~/.config/micro/bindings.json:
--
--     "Ctrl-l": "command:hxpfwd"
--
-- micro binds Ctrl-l to `command-edit:goto ` by default; that prefill is a
-- convenience for the `goto` command, which stays reachable as Ctrl-e goto.

local micro  = import("micro")
local config = import("micro/config")
local shell  = import("micro/shell")

function hxpfwd(bp)
    if bp.Buf.Path == nil or bp.Buf.Path == "" then
        micro.InfoBar():Error("hxp-fwd: buffer is not a file on disk")
        return
    end

    -- micro counts lines and columns from 0; synctex (and hxp-fwd) from 1.
    local line = tostring(bp.Cursor.Y + 1)
    local col  = tostring(bp.Cursor.X + 1)

    -- JobSpawn rather than ExecCommand: for typst there is no synctex, so
    -- hxp-fwd falls back to a pdftotext scan of the whole document, and a
    -- blocking call would freeze the editor for as long as that takes.
    -- nil stdout/stderr callbacks make JobSpawn buffer both streams into the
    -- string handed to onExit, so a failure reports itself instead of vanishing.
    shell.JobSpawn("hxp-fwd", {bp.Buf.AbsPath, line, col}, nil, nil, onHxpFwdExit)
end

function onHxpFwdExit(output, args)
    local msg = output:match("^%s*(.-)%s*$")
    if msg ~= "" then
        micro.InfoBar():Error(msg)
    end
end

function init()
    config.MakeCommand("hxpfwd", hxpfwd, config.NoComplete)
end
