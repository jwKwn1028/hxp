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

function hxperror(bp)
    local output, err = shell.RunCommand("hxp-first-error")
    local text = output:match("^%s*(.-)%s*$")
    if err ~= nil then
        -- A helper that cannot start produces no output.
        if text == "" then text = "hxp-first-error: " .. tostring(err) end
        micro.InfoBar():Error(text)
        return
    end
    -- A bare path is a Markdown error with no mappable line.
    local path, line, col = text:match("^(.*):(%d+):(%d+)$")
    if not path then path = text end
    if path == "" then return end
    if bp.Buf.AbsPath ~= path then
        bp:NewTabCmd({path})
        bp = micro.CurPane()
        if bp.Buf.AbsPath ~= path then return end
    end
    if line then
        bp:GotoCmd({line .. ":" .. col})
    else
        micro.InfoBar():Message("hxp: no Markdown line for this error")
    end
end

function init()
    config.MakeCommand("hxperror", hxperror, config.NoComplete)
    config.MakeCommand("hxpfwd", hxpfwd, config.NoComplete)
end
