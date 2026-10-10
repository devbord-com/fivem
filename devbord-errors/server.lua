-- Sends script errors to the error tracking of devbord (protocol of the Sentry SDKs, via POST /api/<project>/store/).
-- Sources: the server console (every "SCRIPT ERROR" of every resource), the exports captureException/captureMessage,
-- and errors that clients send in. The DSN is on the server only.
-- The server also checks in with a monitor every minute, so devbord notices when it is no longer running.

local RESOURCE = GetCurrentResourceName()
local dsn = GetConvar('devbord_dsn', '')
local release = GetConvar('devbord_release', '')
local environment = GetConvar('devbord_environment', 'production')
local monitor = GetConvar('devbord_monitor', 'fivem-server')
local game = GetConvar('gamename', 'gta5')
local startedAt = os.time()

---@class DevbordFrame
---@field filename string
---@field lineno integer?
---@field function string?
---@field in_app boolean

---@class DevbordCaptureOptions
---@field level? 'fatal'|'error'|'warning'|'info'|'debug'
---@field resource? string resource the error comes from
---@field tags? table<string, string>
---@field extra? table<string, any>
---@field player? integer server ID of the player it happened to
---@field side? 'server'|'client'

---Parses a DSN (https://<key>@host/<project>) into the address errors or check-ins are sent to.
---@param value string
---@param kind 'store'|'envelope'
---@return string? endpoint nil if the DSN is invalid
local function endpointOf(value, kind)
  local scheme, key, host, project = value:match('^(https?)://([%w]+)@([^/]+)/(%d+)$')
  if not scheme then return nil end
  return ('%s://%s/api/%s/%s/?sentry_key=%s&sentry_version=7'):format(scheme, host, project, kind, key)
end

local endpoint = endpointOf(dsn, 'store')
local envelopeEndpoint = endpointOf(dsn, 'envelope')
local sentThisMinute, minuteStart = 0, os.time()
local recent = {} -- message -> time of the last occurrence

local function ignored(resource)
  if not resource then return false end
  for _, name in ipairs(Config.IgnoreResources or {}) do
    if name == resource then return true end
  end
  return false
end

---Turns a traceback into the stack the way devbord expects it (oldest call first).
---Recognises both the format of the server console ("> name (@resource/path.lua:12)") and that of debug.traceback.
---@param trace string?
---@return DevbordFrame[]
local function framesOf(trace)
  local frames = {}
  for line in tostring(trace or ''):gmatch('[^\r\n]+') do
    local file, lineno = line:match('@([^:%s%)]+):(%d+)')
    if file then
      local fn = line:match("in %a+ '([^']+)'") or line:match('in function <([^>]+)>') or line:match('^%s*>%s*([%w_%.:]+)%s*%(')
      frames[#frames + 1] = { filename = file, lineno = tonumber(lineno), ['function'] = fn, in_app = true }
    end
  end
  -- a traceback starts at the error; devbord wants the error last
  local out = {}
  for i = #frames, 1, -1 do out[#out + 1] = frames[i] end
  return out
end

---The player as the user of the error: the chosen identifier and the name, never the IP address.
---@param src integer?
---@return table?
local function userOf(src)
  if not src or src <= 0 or not Config.PlayerIdentifier then return nil end
  local id = nil
  for i = 0, GetNumPlayerIdentifiers(src) - 1 do
    local v = GetPlayerIdentifier(src, i)
    if v and v:match('^' .. Config.PlayerIdentifier .. ':') then id = v break end
  end
  return { id = id or ('server:' .. src), username = GetPlayerName(src) }
end

-- frameworks in order: Qbox also reports itself as qb-core, so it comes first
local FRAMEWORKS = {
  { 'qbx_core', 'qbox' }, { 'qb-core', 'qbcore' }, { 'es_extended', 'esx' }, { 'ox_core', 'ox' }, { 'ND_Core', 'nd' },
  { 'vorp_core', 'vorp' }, { 'rsg-core', 'rsg' },
}

---@return string? framework short name of the framework that is running
local function frameworkOf()
  for _, f in ipairs(FRAMEWORKS) do
    if GetResourceState(f[1]) == 'started' then return f[2] end
  end
  return nil
end

---What the server is running right now, to filter issues on.
---@param resource string? resource the error comes from
---@return table<string, string> tags
---@return table<string, table> contexts
local function contextOf(resource)
  if Config.Context == false then return {}, {} end
  local tags = { game = game, framework = frameworkOf() }
  local artifact = GetConvar('version', ''):match('v%d+%.%d+%.%d+%.(%d+)')
  if artifact then tags.artifact = artifact end
  local build = GetConvar('sv_enforceGameBuild', '')
  if build ~= '' then tags.game_build = build end
  if resource then
    local version = GetResourceMetadata(resource, 'version', 0)
    if version and version ~= '' then tags['resource.version'] = version end
  end
  for k, v in pairs(Config.Tags or {}) do tags[k] = tostring(v) end
  return tags, {
    server = {
      players = GetNumPlayerIndices(),
      max_players = GetConvarInt('sv_maxclients', 0),
      onesync = GetConvar('onesync', 'off'),
      uptime_minutes = math.floor((os.time() - startedAt) / 60),
    },
  }
end

---Sends one error, within the limits from the configuration.
---@param message string
---@param trace string?
---@param opts DevbordCaptureOptions?
---@return boolean sent false if it was dropped (not configured, duplicate or over the limit)
local function send(message, trace, opts)
  opts = opts or {}
  if not endpoint or ignored(opts.resource) then return false end
  message = tostring(message or ''):gsub('%^%d', ''):sub(1, 2000)
  if message == '' then return false end
  local now = os.time()
  if now - minuteStart >= 60 then sentThisMinute, minuteStart = 0, now end
  if sentThisMinute >= (Config.MaxPerMinute or 60) then return false end
  if recent[message] and now - recent[message] < (Config.DedupeSeconds or 10) then return false end
  recent[message] = now
  sentThisMinute = sentThisMinute + 1

  -- "@resource/path.lua:12: what went wrong" -> split into type and message
  local where, text = message:match('^@?([^:%s]+%.lua:%d+):%s*(.+)$')
  local frames = framesOf(trace)
  if #frames == 0 and where then
    local file, lineno = where:match('^(.+):(%d+)$')
    frames = { { filename = file, lineno = tonumber(lineno), in_app = true } }
  end
  local tags, contexts = contextOf(opts.resource)
  tags.side, tags.resource = opts.side or 'server', opts.resource
  for k, v in pairs(opts.tags or {}) do tags[k] = tostring(v) end
  local event = {
    platform = game == 'rdr3' and 'redm' or 'fivem',
    logger = 'script',
    level = opts.level or 'error',
    environment = environment,
    release = release ~= '' and release or nil,
    server_name = Config.ServerName ~= '' and Config.ServerName or GetConvar('sv_hostname', ''):gsub('%^%d', ''):sub(1, 80),
    tags = tags,
    contexts = next(contexts) and contexts or nil,
    extra = opts.extra,
    user = userOf(opts.player),
    sdk = { name = 'devbord.fivem', version = GetResourceMetadata(RESOURCE, 'version', 0) or '0' },
  }
  if trace or where then
    event.exception = { values = { { type = 'ScriptError', value = text or message, stacktrace = { frames = frames } } } }
  else
    event.message = message
  end
  PerformHttpRequest(endpoint, function(status, response)
    if status ~= 200 then
      -- no print with "SCRIPT ERROR": that would trigger the listener below again
      print(('[%s] sending failed (%s): %s'):format(RESOURCE, tostring(status), tostring(response):sub(1, 160)))
    end
  end, 'POST', json.encode(event), { ['Content-Type'] = 'application/json' })
  return true
end

---Reports an error (e.g. the result of xpcall(fn, debug.traceback)).
---@param err any the error message, optionally followed by a traceback
---@param opts DevbordCaptureOptions?
---@return boolean sent
local function captureException(err, opts)
  local textValue = tostring(err)
  local first, rest = textValue:match('^([^\r\n]+)[\r\n]+(.+)$')
  opts = opts or {}
  if not opts.resource then opts.resource = GetInvokingResource() end
  return send(first or textValue, rest or debug.traceback('', 2), opts)
end

---Reports a message without an error (e.g. a warning).
---@param message string
---@param level? 'fatal'|'error'|'warning'|'info'|'debug'
---@param opts DevbordCaptureOptions?
---@return boolean sent
local function captureMessage(message, level, opts)
  opts = opts or {}
  opts.level = level or opts.level or 'info'
  if not opts.resource then opts.resource = GetInvokingResource() end
  return send(message, nil, opts)
end

exports('captureException', captureException)
exports('captureMessage', captureMessage)

-- ---------- Server console: every script error of every resource ----------
-- The console prints an error as a line "SCRIPT ERROR: ..." followed by lines "> function (@resource/path.lua:12)".
-- We collect the lines of one error and send them together shortly after.
local pendingError = nil

local function flushConsole()
  local p = pendingError
  pendingError = nil
  if p then send(p.message, table.concat(p.lines, '\n'), { resource = p.resource }) end
end

if Config.CaptureConsole and RegisterConsoleListener then
  RegisterConsoleListener(function(channel, message)
    if type(message) ~= 'string' then return end
    -- colour codes (^1, ^7) sometimes come before the ">" of a stack line
    message = message:gsub('%^%d', '')
    local resource = type(channel) == 'string' and channel:match('^script:(.+)$') or nil
    if resource == RESOURCE then return end
    local text = message:match('SCRIPT ERROR:%s*(.-)%s*$')
    if text and text ~= '' then
      flushConsole()
      pendingError = { message = text, lines = {}, resource = resource }
      SetTimeout(250, flushConsole)
    elseif pendingError and message:match('^%s*>') and #pendingError.lines < 40 then
      pendingError.lines[#pendingError.lines + 1] = (message:gsub('%s+$', ''))
    end
  end)
end

-- ---------- Errors from players ----------
local perPlayer = {} -- src -> { count, since }

RegisterNetEvent('devbord-errors:client', function(data)
  local src = source
  if not Config.AcceptClient or type(data) ~= 'table' or type(data.message) ~= 'string' then return end
  local now = os.time()
  local p = perPlayer[src]
  if not p or now - p.since >= 60 then p = { count = 0, since = now } perPlayer[src] = p end
  p.count = p.count + 1
  if p.count > (Config.ClientPerMinute or 5) then return end
  local level = ({ fatal = 'fatal', error = 'error', warning = 'warning', info = 'info' })[data.level] or 'error'
  send(data.message:sub(1, 2000), type(data.trace) == 'string' and data.trace:sub(1, 8000) or nil, {
    side = 'client', player = src, level = level,
    resource = type(data.resource) == 'string' and data.resource:sub(1, 60) or nil,
  })
end)

AddEventHandler('playerDropped', function()
  perPlayer[source] = nil
end)

CreateThread(function()
  while true do
    Wait(60000)
    local now = os.time()
    for k, at in pairs(recent) do
      if now - at > 120 then recent[k] = nil end
    end
  end
end)

-- ---------- Heartbeat ----------
-- The server checks in with a monitor; if the check-in stops coming, devbord turns it into an issue. The first check-in
-- creates the monitor with the schedule from here, after that you manage it in devbord under Errors > Monitors.
local heartbeatFailed = false

local function heartbeat()
  local every = math.max(1, math.floor(tonumber(Config.HeartbeatMinutes) or 1))
  local checkIn = json.encode({
    monitor_slug = monitor,
    status = 'ok',
    environment = environment,
    monitor_config = {
      schedule = { type = 'interval', value = every, unit = 'minute' },
      checkin_margin = math.max(1, math.floor(tonumber(Config.HeartbeatMargin) or 5)),
      timezone = 'UTC',
      heartbeat = true,
    },
  })
  PerformHttpRequest(envelopeEndpoint, function(status)
    -- one line per outage, not every minute
    if status ~= 200 and not heartbeatFailed then
      print(('[%s] sending heartbeat failed (%s)'):format(RESOURCE, tostring(status)))
    end
    heartbeatFailed = status ~= 200
  end, 'POST', ('{}\n{"type":"check_in"}\n%s\n'):format(checkIn), { ['Content-Type'] = 'application/x-sentry-envelope' })
end

if envelopeEndpoint and Config.Heartbeat ~= false and monitor ~= '' then
  CreateThread(function()
    while true do
      heartbeat()
      Wait(math.max(1, math.floor(tonumber(Config.HeartbeatMinutes) or 1)) * 60000)
    end
  end)
end

CreateThread(function()
  if not endpoint then
    print(('^3[%s] Not configured: set devbord_dsn "https://<key>@your.domain/<project>" in server.cfg^7'):format(RESOURCE))
  else
    print(('[%s] errors go to devbord%s%s'):format(RESOURCE, Config.CaptureConsole and RegisterConsoleListener and ' (server console + exports)' or ' (exports)',
      Config.Heartbeat ~= false and monitor ~= '' and (', heartbeat to monitor "%s"'):format(monitor) or ''))
  end
end)
