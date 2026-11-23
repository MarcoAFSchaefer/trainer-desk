-- Themes for the dock. A theme is a table of colours and metrics; a theme that
-- leaves a key out takes it from "dark", so a new theme only lists what differs.
local Themes = { list = {}, order = {} }

local function hex(value)
  return { tonumber(value:sub(1, 2), 16) / 255, tonumber(value:sub(3, 4), 16) / 255,
    tonumber(value:sub(5, 6), 16) / 255, 1 }
end

Themes.list.dark = {
  name = "DARK",
  colors = {
    window = hex("14171c"),        -- behind everything
    dock = hex("1b1f26"),          -- a dock's own background
    panel = hex("0f1216"),         -- behind a panel's picture
    tabBar = hex("181c22"),
    tab = hex("1f242c"),
    tabActive = hex("2b323d"),
    tabHover = hex("252b34"),
    text = hex("9aa5b4"),
    textActive = hex("e6ebf2"),
    accent = hex("4f9cf7"),        -- the active tab's marker and drop hints
    border = hex("0a0c0f"),
    splitter = hex("14171c"),
    splitterHot = hex("4f9cf7"),
    empty = hex("5d6875"),         -- placeholder text
  },
  metrics = { tab = 22, splitter = 5, padding = 8, font = 12, minDock = 120, tabMax = 170 },
}
Themes.order[1] = "dark"

-- Colours may be given as "rrggbb" strings or { r, g, b [, a] } tables.
function Themes.register(id, definition)
  if type(id) ~= "string" or not id:match("^[a-z0-9_]+$") or type(definition) ~= "table" then
    return nil, "a theme needs a lowercase id and a table"
  end
  local theme = { name = tostring(definition.name or id):upper(), colors = {}, metrics = {} }
  for key, value in pairs(definition.colors or {}) do
    if type(value) == "string" and value:match("^%x%x%x%x%x%x$") then theme.colors[key] = hex(value)
    elseif type(value) == "table" and tonumber(value[1]) and tonumber(value[2]) and tonumber(value[3]) then
      theme.colors[key] = { value[1], value[2], value[3], value[4] or 1 }
    end
  end
  for key, value in pairs(definition.metrics or {}) do
    if tonumber(value) then theme.metrics[key] = tonumber(value) end
  end
  if not Themes.list[id] then Themes.order[#Themes.order + 1] = id end
  Themes.list[id] = theme
  return true
end

-- The theme to draw with: the chosen one over "dark".
function Themes.resolve(id)
  local base, chosen = Themes.list.dark, Themes.list[id] or Themes.list.dark
  if chosen == base then return base end
  local out = { name = chosen.name, colors = {}, metrics = {} }
  for key, value in pairs(base.colors) do out.colors[key] = chosen.colors[key] or value end
  for key, value in pairs(base.metrics) do out.metrics[key] = chosen.metrics[key] or value end
  return out
end

return Themes
