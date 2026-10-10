-- Receives /bug, checks permission and cooldown, fetches the context from the player
-- and sends the report to devbord (POST /api/v1/fivem/bugreport). After that the server tracks the report
-- and tells the player when it is fixed.

local url = (GetConvar('devbord_url', '') or ''):gsub('/+$', '')
local apiKey = GetConvar('devbord_api_key', '')
local boardId = tonumber(GetConvar('devbord_board_id', ''))

local KVP = 'devbord:report:'
local cooldowns = {}
local pending = {} -- token -> { src, text, at, opts }

local function tell(src, msg)
  TriggerClientEvent('devbord-bugreport:notify', src, msg)
end

local function configured()
  return url:match('^https://') ~= nil and apiKey:match('^db_[a-f0-9]+_') ~= nil
end

local function identifiersOf(src)
  local out = {}
  if not Config.Identifiers or #Config.Identifiers == 0 then return out end
  local wanted = {}
  for _, k in ipairs(Config.Identifiers) do wanted[k] = true end
  for i = 0, GetNumPlayerIdentifiers(src) - 1 do
    local id = GetPlayerIdentifier(src, i)
    local kind = id and id:match('^([%w]+):')
    -- never the IP address
    if kind and kind ~= 'ip' and wanted[kind] then out[#out + 1] = id end
  end
  return out
end

-- the license stays on the server: only to find the player again later
local function licenseOf(src)
  for i = 0, GetNumPlayerIdentifiers(src) - 1 do
    local id = GetPlayerIdentifier(src, i)
    if id and id:match('^license:') then return id end
  end
  return nil
end

local function newToken()
  return ('%x%x%x'):format(math.random(0, 0xffffff), math.random(0, 0xffffff), os.time())
end

---Starts a report for a player: asks the client for location and screenshot and forwards everything.
---@param src number server ID of the player
---@param text string description of the bug
---@param opts? { title?: string, fingerprint?: string, label?: string|false } fingerprint: reports with the same value are collected on one card
---@return boolean started false if the resource is not configured or the description is empty
local function startReport(src, text, opts)
  text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if not configured() or text == '' or not GetPlayerName(src) then return false end
  local token = newToken()
  pending[token] = { src = src, text = text:sub(1, 2000), at = os.time(), opts = type(opts) == 'table' and opts or {} }
  TriggerClientEvent('devbord-bugreport:collect', src, token)
  return true
end

-- other resources: exports['devbord-bugreport']:report(source, 'Vehicle spawns under the map', { fingerprint = 'garage:spawn' })
exports('report', startReport)

RegisterCommand(Config.Command, function(src, args)
  if src == 0 then print('[devbord] /' .. Config.Command .. ' only works in game') return end
  if not configured() then tell(src, Config.Messages.notConfigured) return end
  if Config.Permission and not IsPlayerAceAllowed(src, Config.Permission) then tell(src, Config.Messages.noPermission) return end
  local text = table.concat(args, ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then tell(src, Config.Messages.usage) return end
  if #text < Config.MinLength then tell(src, Config.Messages.tooShort) return end
  local now = os.time()
  local last = cooldowns[src]
  if last and now - last < Config.Cooldown then
    tell(src, Config.Messages.cooldown:format(Config.Cooldown - (now - last)))
    return
  end
  cooldowns[src] = now
  tell(src, Config.Messages.sending)
  startReport(src, text)
end, false)

RegisterNetEvent('devbord-bugreport:context', function(token, data)
  local src = source
  local p = type(token) == 'string' and pending[token] or nil
  -- only accept replies to a recent request of our own
  if not p or p.src ~= src or os.time() - p.at > 60 then return end
  pending[token] = nil
  data = type(data) == 'table' and data or {}

  local shot = nil
  if Config.Screenshot and type(data.screenshot) == 'string' and data.screenshot:match('^data:image/jpeg;base64,') and #data.screenshot < 6000000 then
    shot = data.screenshot
  end
  local coords = type(data.coords) == 'table' and data.coords or {}
  local label = Config.Label
  if p.opts.label ~= nil then label = p.opts.label end
  local body = {
    board_id = boardId,
    list = Config.List ~= '' and Config.List or nil,
    label = label,
    lang = Config.Locale == 'en' and 'en' or 'nl',
    title = type(p.opts.title) == 'string' and p.opts.title:sub(1, 200) or nil,
    fingerprint = type(p.opts.fingerprint) == 'string' and p.opts.fingerprint:sub(1, 200) or nil,
    description = p.text,
    player = { name = GetPlayerName(src), server_id = tonumber(src), identifiers = identifiersOf(src) },
    coords = { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z), heading = tonumber(coords.heading) },
    street = type(data.street) == 'string' and data.street:sub(1, 80) or nil,
    zone = type(data.zone) == 'string' and data.zone:sub(1, 80) or nil,
    vehicle = type(data.vehicle) == 'string' and data.vehicle:sub(1, 60) or nil,
    game_build = type(data.game_build) == 'string' and data.game_build:sub(1, 20) or nil,
    server = Config.ServerName ~= '' and Config.ServerName or GetConvar('sv_hostname', ''):gsub('%^%d', ''):sub(1, 80),
    resource = GetCurrentResourceName() .. ' ' .. (GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or ''),
    screenshot = shot,
  }
  local name = GetPlayerName(src) or tostring(src)
  local license = licenseOf(src)

  PerformHttpRequest(url .. '/api/v1/fivem/bugreport', function(status, response)
    local ok, res = pcall(json.decode, response or '')
    res = ok and type(res) == 'table' and res or {}
    if status == 201 or status == 200 then
      tell(src, (res.duplicate and Config.Messages.sentDuplicate or Config.Messages.sent):format(res.number or '?'))
      print(('[devbord] bug from %s -> card #%s%s'):format(name, tostring(res.number or '?'), res.duplicate and ' (already reported)' or ''))
      if Config.NotifyFixed and license and type(res.receipt) == 'string' then
        SetResourceKvp(KVP .. res.receipt, json.encode({ id = license, number = res.number, at = os.time() }))
      end
    else
      cooldowns[src] = nil -- retrying is allowed right away
      tell(src, Config.Messages.failed)
      print(('[devbord] bug report failed (%s): %s'):format(tostring(status), tostring(res.error or response):sub(1, 200)))
    end
  end, 'POST', json.encode(body), {
    ['Content-Type'] = 'application/json',
    ['Authorization'] = 'Bearer ' .. apiKey,
    -- a retry of the same report does not create a second card
    ['Idempotency-Key'] = token,
  })
end)

AddEventHandler('playerDropped', function()
  cooldowns[source] = nil
end)

-- clean up old requests
CreateThread(function()
  while true do
    Wait(60000)
    local now = os.time()
    for k, v in pairs(pending) do
      if now - v.at > 120 then pending[k] = nil end
    end
  end
end)

-- ---------- Fixed: notify the player ----------
local function followed()
  local out = {}
  local handle = StartFindKvp(KVP)
  if handle == -1 then return out end
  while true do
    local key = FindKvp(handle)
    if not key then break end
    local ok, entry = pcall(json.decode, GetResourceKvpString(key) or '')
    if ok and type(entry) == 'table' and os.time() - (tonumber(entry.at) or 0) < Config.FixedDays * 86400 then
      out[key:sub(#KVP + 1)] = entry
    else
      DeleteResourceKvp(key)
    end
  end
  EndFindKvp(handle)
  return out
end

-- pass on reports that were fixed to whoever is online now
local function deliverFixed(entries)
  local online = {}
  for _, id in ipairs(GetPlayers()) do
    local license = licenseOf(id)
    if license then online[license] = tonumber(id) end
  end
  for receipt, entry in pairs(entries) do
    if entry.fixed and online[entry.id] then
      tell(online[entry.id], Config.Messages.fixed:format(tostring(entry.number or '?')))
      DeleteResourceKvp(KVP .. receipt)
    end
  end
end

local function checkFixed()
  local entries = followed()
  local open = {}
  for receipt, entry in pairs(entries) do
    if not entry.fixed then open[#open + 1] = receipt end
  end
  deliverFixed(entries)
  for i = 1, #open, 100 do
    local batch = {}
    for j = i, math.min(i + 99, #open) do batch[#batch + 1] = open[j] end
    PerformHttpRequest(url .. '/api/v1/reports/status', function(status, response)
      local ok, list = pcall(json.decode, response or '')
      if status ~= 200 or not ok or type(list) ~= 'table' then return end
      local changed = {}
      for _, item in ipairs(list) do
        local entry = type(item) == 'table' and entries[item.receipt]
        if entry and item.state == 'completed' then
          entry.fixed = true
          SetResourceKvp(KVP .. item.receipt, json.encode(entry))
          changed[item.receipt] = entry
        elseif entry and item.state ~= 'open' then
          -- dismissed without a fix, or the card no longer exists
          DeleteResourceKvp(KVP .. item.receipt)
        end
      end
      deliverFixed(changed)
    end, 'POST', json.encode({ receipts = batch }), {
      ['Content-Type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. apiKey,
    })
  end
end

CreateThread(function()
  if not configured() then
    print('^3[devbord] Not configured: set devbord_url (https://...) and devbord_api_key in server.cfg^7')
    return
  end
  print(('[devbord] bug reports go to %s%s'):format(url, boardId and (' (board ' .. boardId .. ')') or ''))
  if not Config.NotifyFixed then return end
  while true do
    Wait(math.max(1, tonumber(Config.StatusInterval) or 5) * 60000)
    checkFixed()
  end
end)

-- whoever joins hears right away what was fixed in the meantime
AddEventHandler('playerJoining', function()
  if not Config.NotifyFixed then return end
  SetTimeout(30000, function() deliverFixed(followed()) end)
end)
