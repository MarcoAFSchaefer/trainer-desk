-- Desktop windows for panels taken out of the dock. The host shows a second
-- display by starting a minimal copy of itself that draws frames received over
-- a loopback ENet link and sends pointer input back; a floating panel is one
-- such companion, keyed by the panel's id.
return function(mod)
  local Windows = { byKey = {}, lastStart = -math.huge }
  local okEnet, enet = pcall(require, "enet")
  local okShell, HostShell = pcall(require, "src.core.HostShell")
  local okPlatform, Platform = pcall(require, "src.core.Platform")
  local START_GAP, CONNECT_TIMEOUT, RETRY = 0.7, 12, 3

  local function now() return love.timer.getTime() end

  function Windows.usable()
    return okEnet and type(enet) == "table" and okShell and type(HostShell) == "table"
      and type(HostShell.spawnSelfDetached) == "function"
      and okPlatform and type(Platform) == "table" and Platform.canSpawnProcess() == true
      and love.data ~= nil and love.data.compress ~= nil
  end

  local function destroy(win, sendQuit)
    if win.peer and sendQuit then
      pcall(win.peer.send, win.peer, "Q" .. win.token, 1, "reliable")
      if win.host then pcall(win.host.flush, win.host) end
    end
    if win.peer then pcall(win.peer.disconnect_now, win.peer) end
    if win.host then pcall(win.host.destroy, win.host) end
    win.host, win.peer, win.token, win.port, win.last = nil, nil, nil, nil, nil
  end

  local function token()
    local seed = table.concat({ tostring(os.time()), tostring(now()), tostring({}), tostring(math.random()) }, ":")
    return love.data.encode("string", "hex", love.data.hash("sha256", seed)):sub(1, 24)
  end

  local function start(win)
    local base = 49152 + math.floor(now() * 1000) % 12000
    for attempt = 0, 31 do
      local port = 49152 + (base - 49152 + attempt * 37) % 12000
      local ok, host = pcall(enet.host_create, ("127.0.0.1:%d"):format(port), 1, 2)
      if ok and host then
        win.host, win.token, win.startedAt = host, token(), now()
        local okSpawn, launched = pcall(HostShell.spawnSelfDetached,
          { ("--display-companion=%d,%s"):format(port, win.token) })
        if okSpawn and launched then
          Windows.lastStart = now()
          return true
        end
        destroy(win, false)
        break
      end
    end
    win.retryAt = now() + RETRY
    win.failures = (win.failures or 0) + 1
    return false
  end

  local function service(win)
    while win.host do
      local ok, event = pcall(win.host.service, win.host, 0)
      if not ok then
        destroy(win, false)
        win.retryAt = now() + RETRY
        return
      end
      if not event then break end
      if event.type == "receive" then
        local data = event.data or ""
        if data == "H" .. win.token then
          win.peer, win.last, win.failures = event.peer, nil, 0
          -- The companion's own UDP port tells its window apart from the others.
          win.port = tonumber(tostring(event.peer):match(":(%d+)$"))
        elseif event.peer == win.peer and data:sub(1, #win.token + 2) == "I" .. win.token .. "\n" then
          if #win.touches < 64 then win.touches[#win.touches + 1] = data:sub(#win.token + 3) end
        elseif event.peer == win.peer and data == "C" .. win.token then
          -- The player closed this window.
          win.closed = true
          destroy(win, false)
          return
        end
      elseif event.type == "disconnect" and event.peer == win.peer then
        destroy(win, false)
        win.retryAt = now() + RETRY
        return
      end
    end
    if win.host and not win.peer and now() - (win.startedAt or 0) > CONNECT_TIMEOUT then
      destroy(win, false)
      win.failures = (win.failures or 0) + 1
      win.retryAt = now() + RETRY * win.failures
    end
    if win.peer and now() >= (win.heartbeatAt or 0) then
      win.heartbeatAt = now() + 1
      pcall(win.peer.send, win.peer, "P" .. win.token, 1, "unreliable")
    end
  end

  -- Keeps exactly the windows named in `wanted` (a set of keys) alive.
  function Windows.update(wanted)
    for key, win in pairs(Windows.byKey) do
      if not wanted[key] then
        destroy(win, true)
        Windows.byKey[key] = nil
      end
    end
    for key in pairs(wanted) do
      local win = Windows.byKey[key]
      if not win then
        win = { touches = {} }
        Windows.byKey[key] = win
      end
      if not win.host and not win.closed and (win.failures or 0) < 5
          and now() >= (win.retryAt or 0) and now() - Windows.lastStart >= START_GAP then
        start(win)
      end
      service(win)
    end
  end

  function Windows.connected(key)
    local win = Windows.byKey[key]
    return win ~= nil and win.peer ~= nil
  end
  -- True once, after the player closes the window or it cannot be opened.
  function Windows.gone(key)
    local win = Windows.byKey[key]
    return win ~= nil and (win.closed == true or (win.failures or 0) >= 5)
  end
  function Windows.touch(key)
    local win = Windows.byKey[key]
    return win and table.remove(win.touches, 1) or nil
  end

  -- Sends a picture; an unchanged picture is not sent again.
  function Windows.push(key, imageData, background, preference)
    local win = Windows.byKey[key]
    if not (win and win.peer and imageData) then return false end
    local w, h = imageData:getDimensions()
    local raw = imageData:getString()
    if raw == win.last then return true end
    local header = ("F%s\n%d,%d,%u,%s\n"):format(win.token, w, h,
      tonumber(background) or 0, (tostring(preference or "auto"):gsub("[^%w_:.-]", "")))
    local sent = pcall(win.peer.send, win.peer,
      header .. love.data.compress("string", "lz4", raw, 1), 0, "reliable")
    if sent then win.last = raw end
    return sent
  end

  -- "dock.a:50123,dock.b:50177": the UDP port each floating window talks from.
  function Windows.ports(prefix)
    local parts = {}
    for key, win in pairs(Windows.byKey) do
      if win.peer and win.port then parts[#parts + 1] = (prefix or "") .. key .. ":" .. win.port end
    end
    table.sort(parts)
    return table.concat(parts, ",")
  end

  function Windows.closeAll()
    for key, win in pairs(Windows.byKey) do
      destroy(win, true)
      Windows.byKey[key] = nil
    end
  end

  return Windows
end
