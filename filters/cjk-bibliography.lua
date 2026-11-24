-- Resolve bibliography metadata from the Markdown directory, like citeproc.
function Meta(meta)
  local font = os.getenv("HXP_CJK_FONT_RESOLVED")
  if meta.CJKmainfont or not meta.bibliography or not font or font == "" then
    return
  end

  local bibliographies = meta.bibliography
  if pandoc.utils.type(bibliographies) ~= "List" then
    bibliographies = { bibliographies }
  end
  for _, bibliography in ipairs(bibliographies) do
    local file = io.open(pandoc.utils.stringify(bibliography), "rb")
    if file then
      local contents = file:read("*a")
      file:close()
      -- Match _hxp_has_cjk lead bytes.
      if contents:find("[\227-\237]") then
        meta.CJKmainfont = pandoc.MetaString(font)
        return meta
      end
    end
  end
end
