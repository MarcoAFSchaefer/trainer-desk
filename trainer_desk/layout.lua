-- The dock's layout model. No drawing and no engine calls here: only where
-- panels live (which dock, which tab group), how big things are, and the
-- rectangles that follow from a window size.
--
--   layout.docks.left|right|bottom = { size = fraction of the window,
--     groups = { { tabs = { panelId, ... }, active = index, weight = n }, ... } }
--
-- Left and right docks run the full height; the bottom dock sits between them.
local Layout = {}
local floor, max, min = math.floor, math.max, math.min
Layout.SIDES = { "left", "right", "bottom" }
local DEFAULT_SIZE = { left = 0.22, right = 0.30, bottom = 0.30 }

-- layout.hidden[id] marks a closed panel and layout.floating[id] one shown in
-- a window of its own; both keep their place in the docks for when they return.
function Layout.new()
  local layout = { docks = {}, hidden = {}, floating = {} }
  for _, side in ipairs(Layout.SIDES) do layout.docks[side] = { size = DEFAULT_SIZE[side], groups = {} } end
  return layout
end

-- "left=0.22|1:1:a,b|2:0.5:c;right=...": one dock per ";", one group per "|".
function Layout.encode(layout)
  local docks = {}
  for _, side in ipairs(Layout.SIDES) do
    local dock = layout.docks[side]
    local parts = { ("%s=%.4f"):format(side, dock.size) }
    for _, group in ipairs(dock.groups) do
      parts[#parts + 1] = ("%d:%.4f:%s"):format(group.active, group.weight, table.concat(group.tabs, ","))
    end
    docks[#docks + 1] = table.concat(parts, "|")
  end
  for _, name in ipairs({ "hidden", "floating" }) do
    local ids = {}
    for id, on in pairs(layout[name]) do if on then ids[#ids + 1] = id end end
    table.sort(ids)
    if #ids > 0 then docks[#docks + 1] = name .. "=" .. table.concat(ids, ",") end
  end
  return table.concat(docks, ";")
end

function Layout.decode(text)
  local layout = Layout.new()
  if type(text) ~= "string" then return layout end
  local seen = {}
  for chunk in text:gmatch("[^;]+") do
    local set, ids = chunk:match("^(%a+)=(.*)$")
    if set == "hidden" or set == "floating" then
      for id in ids:gmatch("[^,]+") do layout[set][id] = true end
    end
    local side, size, rest = chunk:match("^(%a+)=([%d%.]+)(.*)$")
    local dock = side and layout.docks[side]
    if dock then
      dock.size = max(0.08, min(0.7, tonumber(size) or DEFAULT_SIZE[side]))
      for active, weight, tabs in rest:gmatch("|(%d+):([%d%.]+):([^|]*)") do
        local group = { tabs = {}, active = tonumber(active) or 1, weight = max(0.05, tonumber(weight) or 1) }
        for id in tabs:gmatch("[^,]+") do
          if not seen[id] then seen[id] = true; group.tabs[#group.tabs + 1] = id end
        end
        if #group.tabs > 0 then
          group.active = max(1, min(#group.tabs, group.active))
          dock.groups[#dock.groups + 1] = group
        end
      end
    end
  end
  return layout
end

-- Where a panel is: side, group index, tab index.
function Layout.find(layout, id)
  for _, side in ipairs(Layout.SIDES) do
    for g, group in ipairs(layout.docks[side].groups) do
      for t, tab in ipairs(group.tabs) do
        if tab == id then return side, g, t end
      end
    end
  end
end

function Layout.remove(layout, id)
  local side, g, t = Layout.find(layout, id)
  if not side then return false end
  local groups = layout.docks[side].groups
  local group = groups[g]
  table.remove(group.tabs, t)
  if #group.tabs == 0 then table.remove(groups, g)
  else group.active = max(1, min(#group.tabs, t <= group.active and group.active - (t < group.active and 1 or 0) or group.active)) end
  return true
end

-- Puts a panel somewhere. mode: "tab" joins groups[index]; "before"/"after"
-- makes a new group beside groups[index]; "new" appends a new group.
function Layout.place(layout, id, side, mode, index)
  -- Dropping a group's only tab beside its own group changes nothing.
  local fromSide, fromGroup = Layout.find(layout, id)
  local target = layout.docks[side]
  if not target then return false end
  local anchor = index and target.groups[index] or nil
  Layout.remove(layout, id)
  local groups = target.groups
  if mode == "tab" and anchor and anchor.tabs then
    -- the anchor group may have been removed if the panel was its only tab
    local alive = false
    for _, group in ipairs(groups) do alive = alive or group == anchor end
    if alive then
      anchor.tabs[#anchor.tabs + 1] = id
      anchor.active = #anchor.tabs
      return true
    end
  end
  local at = #groups + 1
  if anchor and (mode == "before" or mode == "after") then
    for position, group in ipairs(groups) do
      if group == anchor then at = mode == "before" and position or position + 1 end
    end
  end
  local weight = 1
  if #groups > 0 then
    local total = 0
    for _, group in ipairs(groups) do total = total + group.weight end
    weight = total / #groups
  end
  table.insert(groups, at, { tabs = { id }, active = 1, weight = weight })
  return true, fromSide, fromGroup
end

-- A panel new to the layout goes to the right dock: its own group while that
-- dock has room, otherwise one more tab in the last group.
function Layout.adopt(layout, id, preferred, first)
  if Layout.find(layout, id) then return false end
  local side = layout.docks[preferred] and preferred or "right"
  local groups = layout.docks[side].groups
  if first and #groups > 0 then Layout.place(layout, id, side, "before", 1)
  elseif #groups < 2 then Layout.place(layout, id, side, "new")
  else
    -- one more tab in the last group, without taking the front from the tab being looked at
    local group = groups[#groups]
    local front = group.active
    Layout.place(layout, id, side, "tab", #groups)
    group.active = front
  end
  return true
end

-- Rectangles for a window area. `present(id)` says whether a panel exists
-- right now; groups whose panels are all absent take no room, and a dock with
-- no visible group is closed. Returns:
--   { center = rect, docks = { side = { rect, splitter, groups = { {rect, bar, body, tabs = { {id, rect} }, group, index, splitter} } } } }
function Layout.geometry(layout, area, metrics, present, tabWidth)
  local out = { docks = {} }
  local gap, bar = metrics.splitter, metrics.tab
  local visible = {}
  for _, side in ipairs(Layout.SIDES) do
    visible[side] = {}
    for index, group in ipairs(layout.docks[side].groups) do
      local tabs = {}
      for _, id in ipairs(group.tabs) do if present(id) then tabs[#tabs + 1] = id end end
      if #tabs > 0 then visible[side][#visible[side] + 1] = { group = group, index = index, ids = tabs } end
    end
  end
  local x, y, w, h = area.x, area.y, area.w, area.h
  local function span(side, total)
    if #visible[side] == 0 then return 0 end
    return max(min(metrics.minDock, floor(total * 0.45)), min(floor(total * 0.7), floor(total * layout.docks[side].size)))
  end
  local leftW, rightW = span("left", w), span("right", w)
  if leftW + rightW > w - metrics.minDock then
    local scale = max(0, w - metrics.minDock) / max(1, leftW + rightW)
    leftW, rightW = floor(leftW * scale), floor(rightW * scale)
  end
  local cx, cw = x + leftW, w - leftW - rightW
  local bottomH = span("bottom", h)
  local rects = {
    left = leftW > 0 and { x = x, y = y, w = leftW - gap, h = h } or nil,
    right = rightW > 0 and { x = x + w - rightW + gap, y = y, w = rightW - gap, h = h } or nil,
    bottom = bottomH > 0 and { x = cx, y = y + h - bottomH + gap, w = cw, h = bottomH - gap } or nil,
  }
  local splitters = {
    left = leftW > 0 and { x = x + leftW - gap, y = y, w = gap, h = h } or nil,
    right = rightW > 0 and { x = x + w - rightW, y = y, w = gap, h = h } or nil,
    bottom = bottomH > 0 and { x = cx, y = y + h - bottomH, w = cw, h = gap } or nil,
  }
  out.center = { x = cx, y = y, w = cw, h = h - bottomH }
  for _, side in ipairs(Layout.SIDES) do
    local rect = rects[side]
    if rect then
      local dock = { rect = rect, splitter = splitters[side], groups = {}, side = side }
      local along = side == "bottom" and rect.w or rect.h
      local list = visible[side]
      local total, free = 0, along - gap * (#list - 1)
      for _, entry in ipairs(list) do total = total + entry.group.weight end
      local cursor = side == "bottom" and rect.x or rect.y
      for position, entry in ipairs(list) do
        local size = position == #list
          and (side == "bottom" and rect.x + rect.w or rect.y + rect.h) - cursor
          or floor(free * entry.group.weight / total)
        local r = side == "bottom" and { x = cursor, y = rect.y, w = size, h = rect.h }
          or { x = rect.x, y = cursor, w = rect.w, h = size }
        local view = { rect = r, group = entry.group, index = entry.index, tabs = {}, side = side,
          bar = { x = r.x, y = r.y, w = r.w, h = bar },
          body = { x = r.x, y = r.y + bar, w = r.w, h = max(0, r.h - bar) } }
        local active = entry.group.tabs[entry.group.active]
        local widths, sum, at = {}, 0, nil
        for position2, id in ipairs(entry.ids) do
          -- a tab gives up width to its neighbours only down to a label that can still be read
          widths[position2] = min(metrics.tabMax, max(40, tabWidth and tabWidth(id) or 80), max(72, floor(r.w / #entry.ids)))
          if id == active then
            -- the active tab keeps its whole label: it also carries the two marks
            at = position2
            widths[position2] = min(metrics.tabMax, max(40, tabWidth and tabWidth(id) or 80), max(72, r.w - bar))
          end
          sum = sum + widths[position2]
        end
        view.active = entry.ids[at or 1]
        local first, last, room = 1, #entry.ids, r.w
        if sum > r.w and #entry.ids > 1 then
          -- more tabs than the bar holds: a run of them that includes the
          -- active one, and a button at the end that lists them all
          room = max(40, r.w - bar)
          local function run(from)
            local used, to = 0, from
            for index2 = from, #entry.ids do
              if index2 > from and used + widths[index2] > room then break end
              used, to = used + widths[index2], index2
            end
            return to
          end
          last = run(first)
          while last < (at or 1) do
            first = first + 1
            last = run(first)
          end
          view.more = { x = r.x + r.w - bar, y = r.y, w = bar, h = bar }
        end
        local tx = r.x
        for position2 = first, last do
          local tw = max(1, min(widths[position2], r.x + room - tx))
          view.tabs[#view.tabs + 1] = { id = entry.ids[position2], rect = { x = tx, y = r.y, w = tw, h = bar } }
          tx = tx + tw
        end
        view.ids = entry.ids
        if position < #list then
          view.splitter = side == "bottom" and { x = cursor + size, y = rect.y, w = gap, h = rect.h }
            or { x = rect.x, y = cursor + size, w = rect.w, h = gap }
          view.next = list[position + 1].group
        end
        dock.groups[#dock.groups + 1] = view
        cursor = cursor + size + gap
      end
      out.docks[side] = dock
    end
  end
  return out
end

local function inside(rect, x, y)
  return rect and x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end
Layout.inside = inside

-- What is under a point: { kind = "tab"|"body"|"bar"|"dockSplitter"|"groupSplitter"|"center", ... }
function Layout.hit(geometry, x, y)
  for _, side in ipairs(Layout.SIDES) do
    local dock = geometry.docks[side]
    if dock then
      if inside(dock.splitter, x, y) then return { kind = "dockSplitter", side = side, dock = dock } end
      for _, view in ipairs(dock.groups) do
        if inside(view.splitter, x, y) then return { kind = "groupSplitter", side = side, view = view, dock = dock } end
        if inside(view.more, x, y) then return { kind = "more", side = side, view = view } end
        for _, tab in ipairs(view.tabs) do
          if inside(tab.rect, x, y) then return { kind = "tab", side = side, view = view, id = tab.id } end
        end
        if inside(view.bar, x, y) then return { kind = "bar", side = side, view = view } end
        if inside(view.body, x, y) then return { kind = "body", side = side, view = view } end
      end
    end
  end
  if inside(geometry.center, x, y) then return { kind = "center" } end
  return { kind = "none" }
end

-- Where a dragged tab would land: { side, mode, index, rect } or nil.
function Layout.dropTarget(geometry, area, x, y)
  for _, side in ipairs(Layout.SIDES) do
    local dock = geometry.docks[side]
    if dock then
      for _, view in ipairs(dock.groups) do
        local r = view.rect
        if inside(r, x, y) then
          if inside(view.bar, x, y) then return { side = side, mode = "tab", index = view.index, rect = r } end
          local horizontal = side == "bottom"
          local t = horizontal and (x - r.x) / max(1, r.w) or (y - r.y) / max(1, r.h)
          if t < 0.28 then
            return { side = side, mode = "before", index = view.index,
              rect = horizontal and { x = r.x, y = r.y, w = floor(r.w / 2), h = r.h } or { x = r.x, y = r.y, w = r.w, h = floor(r.h / 2) } }
          elseif t > 0.72 then
            return { side = side, mode = "after", index = view.index,
              rect = horizontal and { x = r.x + floor(r.w / 2), y = r.y, w = r.w - floor(r.w / 2), h = r.h }
                or { x = r.x, y = r.y + floor(r.h / 2), w = r.w, h = r.h - floor(r.h / 2) } }
          end
          return { side = side, mode = "tab", index = view.index, rect = r }
        end
      end
    end
  end
  -- over the game: its edges open (or extend) the dock on that side
  local c = geometry.center
  if inside(c, x, y) then
    local edge = max(48, floor(min(c.w, c.h) * 0.2))
    if x < c.x + edge then return { side = "left", mode = "new", rect = { x = c.x, y = c.y, w = edge, h = c.h } } end
    if x >= c.x + c.w - edge then return { side = "right", mode = "new", rect = { x = c.x + c.w - edge, y = c.y, w = edge, h = c.h } } end
    if y >= c.y + c.h - edge then return { side = "bottom", mode = "new", rect = { x = c.x, y = c.y + c.h - edge, w = c.w, h = edge } } end
  end
end

-- Dragging the divider between a dock and the game.
function Layout.resizeDock(layout, side, area, x, y)
  local dock = layout.docks[side]
  local size
  if side == "left" then size = (x - area.x) / max(1, area.w)
  elseif side == "right" then size = (area.x + area.w - x) / max(1, area.w)
  else size = (area.y + area.h - y) / max(1, area.h) end
  dock.size = max(0.08, min(0.7, size))
end

-- Dragging the divider between two groups of one dock.
function Layout.resizeGroups(view, x, y)
  local a, b = view.group, view.next
  if not b then return end
  local r = view.rect
  local horizontal = view.side == "bottom"
  local sizeA = horizontal and r.w or r.h
  local total, weights = sizeA / max(0.0001, a.weight) * (a.weight + b.weight), a.weight + b.weight
  local wanted = max(40, min(total - 40, (horizontal and x - r.x or y - r.y)))
  a.weight = max(0.05, weights * wanted / max(1, total))
  b.weight = max(0.05, weights - a.weight)
end

return Layout
