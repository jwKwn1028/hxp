VERSION = "1.0.0"

-- Bind "Ctrl-l": "command:hxpfwd" in micro/bindings.json.

local micro  = import("micro")
local config = import("micro/config")
local shell  = import("micro/shell")

function hxpfwd(bp)
    if bp.Buf.Path == nil or bp.Buf.Path == "" then
        micro.InfoBar():Error("hxp-fwd: buffer is not a file on disk")
        return
    end

    -- Convert Micro coordinates to 1-based SyncTeX positions.
    local line = tostring(bp.Cursor.Y + 1)
    local col  = tostring(bp.Cursor.X + 1)

    -- Run asynchronously; Typst text extraction can be slow. Buffer errors for onExit.
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
