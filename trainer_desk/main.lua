-- Trainer Desk: an IDE-style layout for the game window. The game keeps the
-- middle; panels supplied by other mods sit in docks around it, in tabbed
-- groups with draggable dividers. See layout.lua for the model, theme.lua for
-- themes, and the `api` table below for what other mods can call.
return function(mod)
  local G = love.graphics
  local floor, max, min = math.floor, math.max, math.min
  local function module(name)
    return assert(load(assert(mod:read(name)), "@trainer_desk/" .. name))()
  end
  local Themes, Layout = module("theme.lua"), module("layout.lua")
  local Windows = module("windows.lua")(mod)

  mod.options:define({
    { key = "enabled", label = "IDE LAYOUT", type = "toggle", default = true,
      description = "Show panels from other mods in docks around the game. Drag a divider to resize, drag a tab to move a panel." },
    { key = "capture_second_screen", label = "DOCK SECOND SCREEN", type = "toggle", default = true,
      description = "Dock the picture a mod sends to the second screen (such as Kanto Gear in Separate Screens mode) as a panel instead of opening another window." },
    { key = "language", label = "LANGUAGE", type = "choice", default = "pt",
      choices = { { "PORTUGUES", "pt" }, { "ENGLISH", "en" } } },
    { key = "hotkey", label = "HIDE/SHOW KEY", type = "choice", default = "f10",
      choices = { { "F10", "f10" }, { "F9", "f9" }, { "F8", "f8" }, { "F6", "f6" }, { "NONE", "none" } },
      description = "Hides every dock so the game takes the whole window, and brings them back. Panels in their own windows stay open." },
    { key = "reset_layout", label = "RESET LAYOUT", type = "toggle", default = false,
      description = "Turn on to put every panel back in its default place." },
  })
  local function option(key) return mod.options:get(key) end

  local TEXT = {
    pt = { panels = "Painéis", theme = "Tema", reset = "Restaurar layout", window = "janela", closed = "fechado",
      menu = "Menu da IDE", none = "Nenhum painel registrado", float = "Abrir em janela própria", close = "Fechar painel",
      more = "Todas as abas", hide = "Esconder a IDE" },
    en = { panels = "Panels", theme = "Theme", reset = "Reset layout", window = "window", closed = "closed",
      menu = "IDE menu", none = "No panels registered", float = "Open in its own window", close = "Close panel",
      more = "All tabs", hide = "Hide the IDE" },
  }
  local function T(key) return (TEXT[option("language")] or TEXT.pt)[key] or TEXT.en[key] or key end

  local LAYOUT_KEY, THEME_KEY = "layout/v1", "theme"
  local panels, order = {}, {}        -- id -> panel, and registration order
  local layout = Layout.decode(mod.cache and mod.cache.read and mod.cache:read(LAYOUT_KEY) or nil)
  local themeId = mod.cache and mod.cache.read and mod.cache:read(THEME_KEY) or "dark"
  local theme = Themes.resolve(themeId)
  local menu
  local font, fontSize
  local active, geometry, area = false, nil, nil
  local drag, saveAt, logged = nil, nil, {}
  local collapsed = false     -- docks hidden for now, the game has the whole window

  -- Text cut to a number of bytes without splitting a character; text that is
  -- not valid UTF-8 would make the whole window's drawing fail, so it is made plain.
  local okUtf8, utf8lib = pcall(require, "utf8")
  local function clip(str, limit)
    str = tostring(str)
    if #str > limit then
      local cut = limit
      while cut > 0 do
        local byte = str:byte(cut + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        cut = cut - 1
      end
      str = str:sub(1, cut)
    end
    if okUtf8 and not utf8lib.len(str) then str = str:gsub("[\128-\255]", "?") end
    return str
  end

  local function now() return love.timer.getTime() end
  local function enabled() return active and option("enabled") ~= false end
  local function markSave() saveAt = saveAt or now() + 0.5 end
  local function uiFont()
    if not font or fontSize ~= theme.metrics.font then
      fontSize = theme.metrics.font
      font = G.newFont(fontSize)
    end
    return font
  end

  ---------------------------------------------------------------------------
  -- API for other mods:  mod.find("trainer_desk").exports.dock
  ---------------------------------------------------------------------------
  local api = { api = 1, features = { responsive = true, wheel = true } }

  -- register{ id, title, width, height, draw | image, [pointer], [interval], [pixel], [side] }
  --   id        lowercase letters, digits, "_" and "."; unique, and the name the layout remembers
  --   title     the tab's label
  --   width, height   the panel's own picture size in pixels
  --   draw(now) paints the picture; the canvas is already set and cleared
  --   image()   instead of draw: returns a drawable to show (or nil for none)
  --   imageData()   with image: the same picture as ImageData, so the panel can also live in its own window
  --   pointer(action, x, y, amount)   optional; action is "down" | "move" | "up" | "cancel", in picture pixels,
  --             or "wheel" with the pointer's place and amount > 0 for up, < 0 for down
  --   interval  seconds between repaints while visible (default 0.2)
  --   pixel     size of one art pixel in the picture, so scaling keeps pixels even (default 1)
  --   side      where a panel new to the layout goes: "left" | "right" | "bottom"
  --   first     true to open ahead of the panels already in that dock
  --   responsive   true for a panel that draws itself at any size: draw(now, width, height) is
  --             given the room it has in the dock, and width/height above are only where it starts
  -- Returns true, or nil and a reason.
  function api.register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[a-z0-9_%.]+$") then
      return nil, "a panel needs an id of lowercase letters, digits, '_' or '.'"
    end
    local w, h = tonumber(def.width), tonumber(def.height)
    if not w or not h or w < 16 or h < 16 or w > 4096 or h > 4096 then return nil, "width and height must be 16..4096" end
    if type(def.draw) ~= "function" and type(def.image) ~= "function" then return nil, "a panel needs draw or image" end
    local panel = panels[def.id] or {}
    if not panels[def.id] then order[#order + 1] = def.id end
    panel.id, panel.title = def.id, clip(def.title or def.id, 40)
    panel.width, panel.height = floor(w), floor(h)
    panel.draw, panel.image = def.draw, def.image
    panel.imageData = type(def.imageData) == "function" and def.imageData or nil
    panel.pointer = type(def.pointer) == "function" and def.pointer or nil
    panel.interval = max(0.02, tonumber(def.interval) or 0.2)
    panel.pixel = max(1, floor(tonumber(def.pixel) or 1))
    panel.side, panel.first = def.side, def.first == true
    panel.responsive = def.responsive == true and type(def.draw) == "function"
    panel.baseW, panel.baseH = floor(w), floor(h)
    panel.nextAt, panel.failed = 0, nil
    panels[def.id] = panel
    if Layout.adopt(layout, panel.id, panel.side, panel.first) then markSave() end
    return true
  end

  -- The panel leaves the window; the layout keeps its place for next time.
  function api.unregister(id)
    local panel = panels[id]
    if not panel then return false end
    if panel.canvas then panel.canvas:release() end
    panels[id] = nil
    for index, value in ipairs(order) do
      if value == id then table.remove(order, index) break end
    end
    return true
  end

  -- registerTheme(id, { name, colors = {...}, metrics = {...} }); missing keys come from "dark".
  function api.registerTheme(id, definition)
    local ok, err = Themes.register(id, definition)
    -- the theme the player picked earlier may only be registered now
    if ok and id == themeId then theme = Themes.resolve(id) end
    return ok, err
  end
  function api.setTheme(id)
    if not Themes.list[id] then return false end
    themeId, theme = id, Themes.resolve(id)
    if mod.cache and mod.cache.write then mod.cache:write(THEME_KEY, id) end
    return true
  end
  -- "dock.<panel id>:<port>,...": the UDP port each floating panel's window
  -- talks from, for a mod that keeps track of the game's windows.
  function api.windowPorts() return Windows.ports("dock.") end
  -- The colours and metrics in use, for panels that want to match the window.
  function api.theme() return theme end
  -- True while the dock is laying out the window.
  function api.active() return enabled() end
  -- The key that hides and shows the docks, or nil; and whether they are hidden now.
  function api.hotkey()
    local key = option("hotkey")
    return key ~= "none" and key or nil
  end
  function api.collapsed() return collapsed end
  function api.collapse(state)
    collapsed = state == true
    drag, menu = nil, nil
  end
  mod.exports.dock = api

  ---------------------------------------------------------------------------
  -- Second screen as a panel
  ---------------------------------------------------------------------------
  -- A mod draws on the second screen through the bridge the engine hands it
  -- each frame. Handing it this one instead brings that picture into a dock.
  local SCREEN_ID = "second_screen"
  local screen = { touches = {} }
  local bridge = {
    usable = function() return true end,
    available = function() return true end,
    detected = function() return true end,
    scalingAvailable = function() return true end,
    filteringAvailable = function() return true end,
    setEnabled = function(on)
      screen.on = on == true
      if not screen.on then screen.touches = {} end
    end,
    pollTouch = function() return table.remove(screen.touches, 1) end,
    push = function(imageData, w, h)
      if not imageData then return false end
      local ok = pcall(function()
        local iw, ih = imageData:getDimensions()
        if screen.image and screen.w == iw and screen.h == ih then
          screen.image:replacePixels(imageData)
        else
          if screen.image then screen.image:release() end
          screen.image = G.newImage(imageData)
          screen.image:setFilter("nearest", "nearest")
          screen.w, screen.h = iw, ih
        end
        screen.data = imageData
      end)
      if ok then screen.on = true end
      return ok
    end,
  }
  local function capturing() return enabled() and option("capture_second_screen") ~= false end
  local function syncScreenPanel()
    local wanted = capturing() and screen.on and screen.image ~= nil
    local panel = panels[SCREEN_ID]
    if wanted and (not panel or panel.width ~= screen.w or panel.height ~= screen.h) then
      local gear = mod.find and mod.find("kanto_gear")
      api.register({
        id = SCREEN_ID, title = gear and "Kanto Gear" or "Second screen", side = "right", first = true,
        width = screen.w, height = screen.h,
        image = function() return screen.image end,
        imageData = function() return screen.data end,
        pointer = function(action, x, y)
          if #screen.touches < 64 then
            screen.touches[#screen.touches + 1] = ("%s,%d,%d"):format(action,
              max(0, min(screen.w - 1, floor(x))), max(0, min(screen.h - 1, floor(y))))
          end
        end,
      })
    elseif not wanted and panel then
      api.unregister(SCREEN_ID)
    end
  end

  ---------------------------------------------------------------------------
  -- Geometry
  ---------------------------------------------------------------------------
  -- A panel can float only if it can hand over its picture as data and this
  -- host can open more windows.
  local function canFloat(panel)
    return panel ~= nil and (panel.draw ~= nil or panel.imageData ~= nil) and Windows.usable()
  end
  local function floating(id) return layout.floating[id] == true and canFloat(panels[id]) end
  local function present(id) return panels[id] ~= nil and not layout.hidden[id] and not floating(id) end
  -- Every panel in registration order: { id, title, state = "docked" | "window" | "closed" }.
  function api.panels()
    local out = {}
    for _, id in ipairs(order) do
      out[#out + 1] = { id = id, title = panels[id].title,
        state = floating(id) and "window" or layout.hidden[id] and "closed" or "docked" }
    end
    return out
  end
  -- show(id, "docked" | "window" | "closed"): where a panel lives.
  function api.show(id, state)
    if not panels[id] then return false end
    if state == "window" and not canFloat(panels[id]) then return false end
    layout.hidden[id] = state == "closed" or nil
    layout.floating[id] = state == "window" or nil
    markSave()
    return true
  end
  local ICONS = 32          -- room on every tab for the "own window" and "close" marks
  local function tabWidth(id)
    local panel = panels[id]
    return panel and uiFont():getWidth(panel.title) + theme.metrics.padding * 2 + ICONS or 60
  end
  -- The tab's two marks; only the active tab shows them.
  local function tabIcons(rect)
    local y = rect.y + floor((rect.h - 12) / 2)
    return { x = rect.x + rect.w - 31, y = y, w = 12, h = 12 }, { x = rect.x + rect.w - 16, y = y, w = 12, h = 12 }
  end
  -- The menu button rides in the game area's top-right corner.
  local function handleRect()
    local c = geometry and geometry.center
    return c and { x = c.x + c.w - 28, y = c.y + 6, w = 22, h = 22 } or nil
  end
  local function recompute(rect)
    area = rect
    geometry = Layout.geometry(layout, rect, theme.metrics, present, tabWidth)
    return geometry
  end
  -- Where a panel's picture sits inside a group's body, and its scale.
  local function pictureRect(panel, body)
    local scale = min(body.w / panel.width, body.h / panel.height)
    -- Keep art pixels even when that costs little room; otherwise fill the
    -- space and let the picture be smoothed.
    local unit = 1 / panel.pixel
    local even = floor(scale / unit) * unit
    if even >= unit and even >= scale * 0.88 then scale = even end
    local w, h = panel.width * scale, panel.height * scale
    return { x = floor(body.x + (body.w - w) / 2), y = floor(body.y + (body.h - h) / 2), w = w, h = h, scale = scale }
  end

  ---------------------------------------------------------------------------
  -- Painting
  ---------------------------------------------------------------------------
  local function color(c, alpha) G.setColor(c[1], c[2], c[3], alpha or c[4] or 1) end
  local function fill(rect, c, alpha) color(c, alpha); G.rectangle("fill", rect.x, rect.y, rect.w, rect.h) end

  -- Repaints a panel's own picture when it is due.
  -- bw, bh: the room a docked responsive panel has; it is redrawn to fit as soon as that changes.
  local function refresh(panel, clock, bw, bh)
    if not panel.draw then return false end
    local resized = false
    if panel.responsive and bw and bh then
      bw, bh = max(16, min(4096, floor(bw))), max(16, min(4096, floor(bh)))
      resized = bw ~= panel.width or bh ~= panel.height
      panel.width, panel.height = bw, bh
    end
    if clock < (panel.nextAt or 0) and not resized then return false end
    panel.nextAt = clock + panel.interval
    if not panel.canvas or panel.canvas:getWidth() ~= panel.width or panel.canvas:getHeight() ~= panel.height then
      if panel.canvas then panel.canvas:release() end
      panel.canvas = G.newCanvas(panel.width, panel.height, { dpiscale = 1 })
    end
    local depth = G.getStackDepth()
    G.push("all")
    G.setCanvas(panel.canvas)
    G.origin(); G.setScissor(); G.setShader(); G.setBlendMode("alpha"); G.setColor(1, 1, 1, 1)
    G.clear(theme.colors.panel[1], theme.colors.panel[2], theme.colors.panel[3], 1)
    local ok, err = pcall(panel.draw, clock, panel.width, panel.height)
    while G.getStackDepth() > depth do G.pop() end
    panel.failed = not ok and tostring(err) or nil
    if not ok and not logged[panel.id] then
      logged[panel.id] = true
      mod.log:warn("panel %s: %s", panel.id, tostring(err))
    end
    return true
  end

  local function drawGroup(view, clock, mx, my)
    local colors, metrics = theme.colors, theme.metrics
    fill(view.bar, colors.tabBar)
    for _, tab in ipairs(view.tabs) do
      local panel = panels[tab.id]
      local current = tab.id == view.active
      local hover = Layout.inside(tab.rect, mx, my)
      fill(tab.rect, current and colors.tabActive or hover and colors.tabHover or colors.tab)
      if current then fill({ x = tab.rect.x, y = tab.rect.y, w = tab.rect.w, h = 2 }, colors.accent) end
      fill({ x = tab.rect.x + tab.rect.w - 1, y = tab.rect.y, w = 1, h = tab.rect.h }, colors.border)
      G.setScissor(tab.rect.x, tab.rect.y, max(1, tab.rect.w - (current and ICONS or 1)), tab.rect.h)
      color(current and colors.textActive or colors.text)
      G.print(panel.title, tab.rect.x + metrics.padding, tab.rect.y + floor((metrics.tab - fontSize) / 2) - 1)
      G.setScissor()
      if current then
        local pop, close = tabIcons(tab.rect)
        G.setLineWidth(1)
        if canFloat(panel) then
          color(Layout.inside(pop, mx, my) and colors.accent or colors.text)
          G.rectangle("line", pop.x + 1.5, pop.y + 3.5, 7, 7)
          G.line(pop.x + 4.5, pop.y + 1.5, pop.x + 10.5, pop.y + 1.5, pop.x + 10.5, pop.y + 7.5)
        end
        color(Layout.inside(close, mx, my) and colors.accent or colors.text)
        G.line(close.x + 2.5, close.y + 2.5, close.x + 9.5, close.y + 9.5)
        G.line(close.x + 9.5, close.y + 2.5, close.x + 2.5, close.y + 9.5)
      end
    end
    if view.more then
      local m = view.more
      fill(m, Layout.inside(m, mx, my) and colors.tabHover or colors.tab)
      color(colors.textActive); G.setLineWidth(1)
      local cx, cy = m.x + floor(m.w / 2) + 0.5, m.y + floor(m.h / 2) + 0.5
      G.line(cx - 4, cy - 2, cx, cy + 2, cx + 4, cy - 2)
    end
    fill(view.body, colors.panel)
    local panel = panels[view.active]
    if not panel or view.body.h < 8 then return end
    refresh(panel, clock, view.body.w, view.body.h)
    local picture = panel.draw and panel.canvas or panel.image and panel.image() or nil
    if picture then
      local r = pictureRect(panel, view.body)
      local whole = r.scale * panel.pixel
      picture:setFilter(whole >= 1 and whole == floor(whole) and "nearest" or "linear",
        whole >= 1 and "nearest" or "linear")
      G.setColor(1, 1, 1, 1)
      G.setScissor(view.body.x, view.body.y, view.body.w, view.body.h)
      G.draw(picture, r.x, r.y, 0, r.scale, r.scale)
      G.setScissor()
    else
      color(colors.empty)
      G.printf("...", view.body.x, view.body.y + floor(view.body.h / 2) - fontSize, view.body.w, "center")
    end
    if panel.failed then
      color(colors.empty)
      G.printf(clip(panel.failed, 160), view.body.x + 6, view.body.y + 6, max(20, view.body.w - 12), "left")
    end
  end

  local function drawDocks()
    if not geometry then return end
    local clock = now()
    local colors = theme.colors
    local mx, my = -1, -1
    if love.mouse and love.mouse.getPosition then mx, my = love.mouse.getPosition() end
    G.setFont(uiFont())
    for _, side in ipairs(Layout.SIDES) do
      local dock = geometry.docks[side]
      if dock then
        fill(dock.rect, colors.dock)
        local hot = drag and drag.kind == "dock" and drag.side == side
          or not drag and Layout.inside(dock.splitter, mx, my)
        fill(dock.splitter, hot and colors.splitterHot or colors.splitter)
        for _, view in ipairs(dock.groups) do
          drawGroup(view, clock, mx, my)
          if view.splitter then
            local warm = drag and drag.kind == "group" and drag.group == view.group
              or not drag and Layout.inside(view.splitter, mx, my)
            fill(view.splitter, warm and colors.splitterHot or colors.splitter)
          end
        end
      end
    end
    -- a tab being dragged: where it would land, and its label at the pointer
    if drag and drag.kind == "tab" and drag.moving then
      local target = Layout.dropTarget(geometry, area, drag.x, drag.y)
      if target then
        fill(target.rect, colors.accent, 0.22)
        color(colors.accent); G.setLineWidth(2)
        G.rectangle("line", target.rect.x + 1, target.rect.y + 1, target.rect.w - 2, target.rect.h - 2)
      end
      local panel = panels[drag.id]
      if panel then
        local w = uiFont():getWidth(panel.title) + theme.metrics.padding * 2
        fill({ x = drag.x + 10, y = drag.y + 10, w = w, h = theme.metrics.tab }, colors.tabActive, 0.95)
        color(colors.textActive)
        G.print(panel.title, drag.x + 10 + theme.metrics.padding, drag.y + 10 + floor((theme.metrics.tab - fontSize) / 2) - 1)
      end
    end
    -- what the small marks do, said next to the pointer
    if not drag and not menu then
      local tip
      for _, side in ipairs(Layout.SIDES) do
        for _, view in ipairs(geometry.docks[side] and geometry.docks[side].groups or {}) do
          if Layout.inside(view.more, mx, my) then tip = T("more") end
          for _, tab in ipairs(view.tabs) do
            if tab.id == view.active then
              local pop, close = tabIcons(tab.rect)
              if Layout.inside(close, mx, my) then tip = T("close")
              elseif Layout.inside(pop, mx, my) and canFloat(panels[tab.id]) then tip = T("float") end
            end
          end
        end
      end
      if tip then
        local w = uiFont():getWidth(tip) + 12
        local box = { x = max(area.x, min(mx + 12, area.x + area.w - w)), y = my + 16, w = w, h = fontSize + 8 }
        fill({ x = box.x - 1, y = box.y - 1, w = box.w + 2, h = box.h + 2 }, colors.border)
        fill(box, colors.tabActive)
        color(colors.textActive)
        G.print(tip, box.x + 6, box.y + 3)
      end
    end
    -- the menu button, faint until the pointer comes near
    local handle = handleRect()
    if handle then
      local near = menu ~= nil or Layout.inside({ x = handle.x - 30, y = handle.y - 6, w = handle.w + 36, h = handle.h + 36 }, mx, my)
      fill(handle, colors.tabActive, near and 0.95 or 0.35)
      color(near and colors.textActive or colors.text, near and 1 or 0.6)
      for row = 0, 2 do G.rectangle("fill", handle.x + 5, handle.y + 6 + row * 4, handle.w - 10, 2) end
    end
    if menu then
      local rowH = theme.metrics.tab
      fill({ x = menu.x - 1, y = menu.y - 1, w = menu.w + 2, h = menu.h + 2 }, colors.border)
      fill(menu, colors.tabBar)
      for index, item in ipairs(menu.items) do
        local row = { x = menu.x, y = menu.y + (index - 1) * rowH, w = menu.w, h = rowH }
        if item.header then
          fill(row, colors.dock)
          color(colors.empty)
          G.print(item.label, row.x + theme.metrics.padding, row.y + floor((rowH - fontSize) / 2) - 1)
        else
          if Layout.inside(row, mx, my) then fill(row, colors.tabHover) end
          if item.checked then fill({ x = row.x + 8, y = row.y + floor(rowH / 2) - 3, w = 6, h = 6 }, colors.accent) end
          color(item.checked and colors.textActive or colors.text)
          G.print(item.label, row.x + 22, row.y + floor((rowH - fontSize) / 2) - 1)
          if item.note then
            color(colors.empty)
            G.print(item.note, row.x + row.w - uiFont():getWidth(item.note) - theme.metrics.padding,
              row.y + floor((rowH - fontSize) / 2) - 1)
          end
        end
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Menu: which panels are shown, the theme, and resetting the layout
  ---------------------------------------------------------------------------
  local function resetLayout()
    layout = Layout.new()
    for _, id in ipairs(order) do Layout.adopt(layout, id, panels[id].side, panels[id].first) end
  end
  local function openMenu(x, y)
    local items = { { header = true, label = T("panels") } }
    for _, id in ipairs(order) do
      local panel = panels[id]
      local away = floating(id)
      items[#items + 1] = { label = panel.title, checked = present(id),
        note = away and T("window") or layout.hidden[id] and T("closed") or nil,
        action = function()
          -- a closed or floating panel comes back to its dock; a docked one closes
          if away or layout.hidden[id] then layout.floating[id], layout.hidden[id] = nil, nil
          else layout.hidden[id] = true end
        end }
    end
    if #order == 0 then items[#items + 1] = { header = true, label = T("none") } end

    items[#items + 1] = { header = true, label = T("theme") }
    for _, id in ipairs(Themes.order) do
      items[#items + 1] = { label = Themes.list[id].name, checked = id == themeId, action = function() api.setTheme(id) end }
    end
    items[#items + 1] = { header = true, label = "" }
    items[#items + 1] = { label = T("reset"), action = resetLayout }
    if api.hotkey() then
      items[#items + 1] = { label = T("hide"), note = api.hotkey():upper(), action = function() api.collapse(true) end }
    end
    local w = 160
    for _, item in ipairs(items) do
      w = max(w, uiFont():getWidth(item.label) + 40 + (item.note and uiFont():getWidth(item.note) + 16 or 0))
    end
    local h = #items * theme.metrics.tab
    local bounds = area or { x = 0, y = 0, w = x + w, h = y + h }
    menu = { items = items, w = w, h = h, main = true,
      x = max(bounds.x, min(x - w, bounds.x + bounds.w - w)), y = max(bounds.y, min(y, bounds.y + bounds.h - h)) }
  end
  -- The tabs of one group, for a bar too narrow to show them all.
  local function openTabs(view)
    local items = {}
    for index, id in ipairs(view.group.tabs) do
      if present(id) then
        items[#items + 1] = { label = panels[id].title, checked = id == view.active,
          action = function() view.group.active = index end }
      end
    end
    local w = 120
    for _, item in ipairs(items) do w = max(w, uiFont():getWidth(item.label) + 40) end
    local h = #items * theme.metrics.tab
    local x, y = view.more.x + view.more.w, view.more.y + view.more.h
    menu = { items = items, w = w, h = h,
      x = max(area.x, min(x - w, area.x + area.w - w)), y = max(area.y, min(y, area.y + area.h - h)) }
  end
  -- A click while the menu is open: run the row under it, or close the menu.
  local function menuPress(x, y)
    if not Layout.inside(menu, x, y) then menu = nil return end
    local item = menu.items[floor((y - menu.y) / theme.metrics.tab) + 1]
    if item and item.action then
      local main = menu.main
      item.action()
      markSave()
      if not (main and menu) then menu = nil return end
      -- rebuild so marks follow what just changed, in the same place
      local mx, my, mw = menu.x, menu.y, menu.w
      openMenu(mx + mw, my)
    end
  end

  ---------------------------------------------------------------------------
  -- Pointer
  ---------------------------------------------------------------------------
  local function toPanel(panel, body, x, y)
    local r = pictureRect(panel, body)
    return (x - r.x) / r.scale, (y - r.y) / r.scale
  end
  local function send(panel, action, x, y)
    if not (panel and panel.pointer) then return end
    local ok, err = pcall(panel.pointer, action, x, y)
    if not ok and not logged[panel.id .. ":pointer"] then
      logged[panel.id .. ":pointer"] = true
      mod.log:warn("panel %s pointer: %s", panel.id, tostring(err))
    end
  end

  -- Returns true when the dock takes the event.
  local function pointer(event)
    local x, y = event.x, event.y
    if event.phase == "pressed" then
      if drag or not geometry or not x then return drag ~= nil end
      if menu then
        menuPress(x, y)
        drag = { kind = "menu", pointer = event.id }
        return true
      end
      if Layout.inside(handleRect(), x, y) then
        local handle = handleRect()
        openMenu(handle.x + handle.w, handle.y + handle.h + 2)
        drag = { kind = "menu", pointer = event.id }
        return true
      end
      if event.button ~= nil and event.button ~= 1 then return Layout.hit(geometry, x, y).kind ~= "center" end
      local hit = Layout.hit(geometry, x, y)
      if hit.kind == "center" or hit.kind == "none" then return false end
      drag = { id = nil, pointer = event.id, x = x, y = y }
      if hit.kind == "more" then
        openTabs(hit.view)
        drag.kind = "menu"
      elseif hit.kind == "dockSplitter" then
        drag.kind, drag.side = "dock", hit.side
      elseif hit.kind == "groupSplitter" then
        drag.kind, drag.group, drag.view = "group", hit.view.group, hit.view
      elseif hit.kind == "tab" and hit.id == hit.view.active and x >= hit.view.bar.x then
        -- the active tab's marks: own window, close
        local rect
        for _, tab in ipairs(hit.view.tabs) do if tab.id == hit.id then rect = tab.rect end end
        local pop, close = tabIcons(rect)
        if Layout.inside(close, x, y) then
          layout.hidden[hit.id] = true
          drag.kind = "bar"
          markSave()
        elseif Layout.inside(pop, x, y) and canFloat(panels[hit.id]) then
          layout.floating[hit.id] = true
          drag.kind = "bar"
          markSave()
        else
          drag.kind, drag.id, drag.startX, drag.startY = "tab", hit.id, x, y
        end
      elseif hit.kind == "tab" then
        drag.kind, drag.id, drag.startX, drag.startY = "tab", hit.id, x, y
        for index, id in ipairs(hit.view.group.tabs) do
          if id == hit.id and hit.view.group.active ~= index then
            hit.view.group.active = index
            markSave()
          end
        end
      elseif hit.kind == "body" then
        local panel = panels[hit.view.active]
        drag.kind, drag.id, drag.body = "panel", hit.view.active, hit.view.body
        if panel then send(panel, "down", toPanel(panel, hit.view.body, x, y)) end
      else
        drag.kind = "bar"
      end
      return true
    end
    if not drag or (event.id ~= nil and drag.pointer ~= nil and event.id ~= drag.pointer) then return false end
    if event.phase == "moved" then
      if not x then return true end
      drag.x, drag.y = x, y
      if drag.kind == "dock" then
        Layout.resizeDock(layout, drag.side, area, x, y)
      elseif drag.kind == "group" then
        -- the view's rectangle moves as weights change: look it up afresh
        for _, side in ipairs(Layout.SIDES) do
          for _, view in ipairs(geometry and geometry.docks[side] and geometry.docks[side].groups or {}) do
            if view.group == drag.group then Layout.resizeGroups(view, x, y) end
          end
        end
      elseif drag.kind == "tab" then
        if not drag.moving and math.abs(x - drag.startX) + math.abs(y - drag.startY) > 10 then drag.moving = true end
      elseif drag.kind == "panel" then
        local panel = panels[drag.id]
        if panel then send(panel, "move", toPanel(panel, drag.body, x, y)) end
      end
      if drag.kind == "dock" or drag.kind == "group" then
        if area then recompute(area) end
        markSave()
      end
      return true
    end
    -- released or cancelled
    local done = drag
    drag = nil
    if done.kind == "panel" then
      local panel = panels[done.id]
      if panel then
        if event.phase == "released" and x then send(panel, "up", toPanel(panel, done.body, x, y))
        else send(panel, "cancel", 0, 0) end
      end
    elseif done.kind == "tab" and done.moving and event.phase == "released" and geometry and x then
      local target = Layout.dropTarget(geometry, area, x, y)
      if target then
        Layout.place(layout, done.id, target.side, target.mode, target.index)
        markSave()
      end
    end
    return true
  end

  ---------------------------------------------------------------------------
  -- Housekeeping and hooks
  ---------------------------------------------------------------------------
  local function housekeeping()
    if option("reset_layout") == true then
      resetLayout()
      if mod.options.set then mod.options:set("reset_layout", false) end
      markSave()
    end
    syncScreenPanel()
    if saveAt and now() >= saveAt and not drag then
      saveAt = nil
      if mod.cache and mod.cache.write then mod.cache:write(LAYOUT_KEY, Layout.encode(layout)) end
    end
  end

  -- Lower priority than a mod that lays out its own views (Kanto Gear's
  -- combined mode uses 1000): such a mod is then given the dock's middle
  -- area to work in, instead of the whole window.
  mod.hooks:wrap("render.viewport", function(nextHook, context)
    local available = nextHook(context)
    geometry = nil
    if not (enabled() and context) then return available end
    if collapsed then
      -- the second screen stays captured and floating windows stay open; only the docks go
      pcall(housekeeping)
      return available
    end
    local ok, result = pcall(function()
      housekeeping()
      local base = type(available) == "table" and available or {}
      local rect = { x = base.x or 0, y = base.y or 0, w = base.width or context.width, h = base.height or context.height }
      recompute(rect)
      local c = geometry.center
      -- capture even with every dock closed, so the menu button stays reachable
      return { x = c.x, y = c.y, width = max(1, c.w), height = max(1, c.h), capture = true }
    end)
    if ok then return result end
    geometry = nil
    if not logged.viewport then logged.viewport = true; mod.log:warn("layout: %s", tostring(result)) end
    return available
  end, 0)

  mod.hooks:wrap("render.window", function(nextHook, windowGame, context)
    local result = nextHook(windowGame, context)
    if geometry and enabled() then
      local depth = G.getStackDepth()
      G.push("all")
      G.origin(); G.setScissor(); G.setShader(); G.setBlendMode("alpha"); G.setLineWidth(1)
      local ok, err = pcall(drawDocks)
      while G.getStackDepth() > depth do G.pop() end
      if not ok and not logged.draw then logged.draw = true; mod.log:warn("draw: %s", tostring(err)) end
    end
    return result
  end, 0)

  -- Ahead of mods that take game-window touches of their own.
  mod.hooks:wrap("input.pointer", function(nextHook, pointerGame, event)
    if enabled() and not collapsed and type(event) == "table" then
      local ok, taken = pcall(pointer, event)
      if ok and taken then return true end
      if not ok then
        drag = nil
        if not logged.pointer then logged.pointer = true; mod.log:warn("pointer: %s", tostring(taken)) end
      end
    end
    return nextHook(pointerGame, event)
  end, 2000)

  -- The wheel over a panel belongs to the panel, not to the game's zoom.
  mod.hooks:wrap("input.wheel", function(nextHook, wheelGame, dy, ...)
    if enabled() and not collapsed and geometry and type(dy) == "number" and love.mouse and love.mouse.getPosition then
      local ok, taken = pcall(function()
        local x, y = love.mouse.getPosition()
        local hit = Layout.hit(geometry, x, y)
        if hit.kind == "center" or hit.kind == "none" then return false end
        if hit.kind == "body" and dy ~= 0 then
          local panel = panels[hit.view.active]
          if panel and panel.pointer then
            local px, py = toPanel(panel, hit.view.body, x, y)
            local okSend, err = pcall(panel.pointer, "wheel", px, py, dy)
            if not okSend and not logged[panel.id .. ":wheel"] then
              logged[panel.id .. ":wheel"] = true
              mod.log:warn("panel %s wheel: %s", panel.id, tostring(err))
            end
          end
        end
        return true
      end)
      if ok and taken then return end
    end
    return nextHook(wheelGame, dy, ...)
  end, 2000)

  -- Esc closes an open menu; the chosen key hides and shows the docks.
  mod.hooks:wrap("input.key", function(nextHook, keyGame, event, ...)
    if enabled() and type(event) == "table" then
      if menu and event.key == "escape" then
        if event.phase == "pressed" then menu, drag = nil, nil end
        return
      end
      if api.hotkey() and event.key == api.hotkey() then
        if event.phase == "pressed" then api.collapse(not collapsed) end
        return
      end
    end
    return nextHook(keyGame, event, ...)
  end, 3500)

  -- Ahead of the mod that draws on the second screen, so it is handed the
  -- dock's bridge in place of the engine's own.
  mod.hooks:wrap("render.compose", function(nextHook, renderer, context)
    if type(context) == "table" and capturing() then context.secondScreen = bridge end
    return nextHook(renderer, context)
  end, 2000)

  -- Floating panels: keep their windows open, send each its picture, and
  -- bring its pointer input back to the panel.
  local function floatingTick()
    local wanted = {}
    if enabled() then
      for _, id in ipairs(order) do
        if floating(id) and not layout.hidden[id] then wanted[id] = true end
      end
    end
    Windows.update(wanted)
    local clock = now()
    for id in pairs(wanted) do
      local panel = panels[id]
      if Windows.gone(id) then
        -- its window was closed: the panel returns to its dock
        layout.floating[id] = nil
        markSave()
      elseif Windows.connected(id) then
        if panel.draw then
          -- in a window of its own a responsive panel is drawn at the size it registered with
          if refresh(panel, clock, panel.responsive and panel.baseW or nil, panel.baseH) or not panel.sentOnce then
            panel.sentOnce = Windows.push(id, panel.canvas:newImageData(), 0x0d0f14, "secondary:fit:auto")
          end
        else
          local data = panel.imageData()
          if data then Windows.push(id, data, 0x0d0f14, "secondary:fit:auto") end
        end
        for _ = 1, 32 do
          local touch = Windows.touch(id)
          if not touch then break end
          local action, tx, ty = touch:match("^(%a+),(%d+),(%d+)$")
          if action then send(panel, action, tonumber(tx), tonumber(ty)) end
        end
      else
        panel.sentOnce = nil
      end
    end
  end
  mod.hooks:wrap("core.update", function(nextHook, updateGame, dt)
    local ok, err = pcall(floatingTick)
    if not ok and not logged.floating then logged.floating = true; mod.log:warn("floating panels: %s", tostring(err)) end
    return nextHook(updateGame, dt)
  end, 890)

  mod.hooks:wrap("core.quit_to_launcher", function(nextHook)
    active, geometry, drag, menu = false, nil, nil, nil
    pcall(Windows.closeAll)
    return nextHook()
  end, 900)
  mod.events:on("game.ready", function()
    active = true
    mod.log:info("ready")
  end)
end
