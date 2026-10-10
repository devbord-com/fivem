-- Catches script errors on the client that nobody catches, and sends them to devbord through devbord-errors.
-- The server sees its own errors in the console; a client has no such console to listen to, so every resource
-- whose client errors you want adds this file as its first client script:
--
--   client_script '@devbord-errors/capture.lua'
--
-- It wraps the functions a resource hands its code to (threads, event handlers, commands, NUI callbacks, timers).
-- An error is reported and then raised again, so it still shows in the F8 console as before.

if IsDuplicityVersion() then return end

local RESOURCE = GetCurrentResourceName()
local MAX_PER_MINUTE = 5
local DEDUPE_SECONDS = 10
local sent, minuteStart = 0, GetGameTimer()
local recent = {} -- message -> time of the last occurrence

---Sends one error to the server, at most a few per minute and the same one once per ten seconds.
---@param err any
---@return any err unchanged, for xpcall
local function report(err)
  local message = tostring(err)
  local now = GetGameTimer()
  if now - minuteStart >= 60000 then sent, minuteStart = 0, now end
  if sent >= MAX_PER_MINUTE or (recent[message] and now - recent[message] < DEDUPE_SECONDS * 1000) then return err end
  recent[message] = now
  sent = sent + 1
  local lines = {}
  for line in debug.traceback('', 2):gmatch('[^\r\n]+') do
    -- the wrapper itself is not part of the error
    if not line:find('devbord-errors/capture.lua', 1, true) and not line:find('[C]: in', 1, true) then lines[#lines + 1] = line end
  end
  TriggerServerEvent('devbord-errors:client', {
    message = message:sub(1, 2000),
    trace = table.concat(lines, '\n'):sub(1, 8000),
    level = 'error',
    resource = RESOURCE,
  })
  return err
end

---Wraps a function so an error in it is reported before it goes on to the console.
---@generic F: function
---@param fn F
---@return F
local function guard(fn)
  if type(fn) ~= 'function' then return fn end
  return function(...)
    local result = table.pack(xpcall(fn, report, ...))
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
  end
end

---Replaces a function by one that guards the callback it is given.
---@param owner table where the function lives (_G or Citizen)
---@param name string
---@param position integer which argument is the callback
local function wrap(owner, name, position)
  local original = owner[name]
  if type(original) ~= 'function' then return end
  owner[name] = function(...)
    local args = table.pack(...)
    args[position] = guard(args[position])
    return original(table.unpack(args, 1, args.n))
  end
end

wrap(_G, 'CreateThread', 1)
wrap(_G, 'SetTimeout', 2)
wrap(_G, 'AddEventHandler', 2)
wrap(_G, 'RegisterNetEvent', 2)
wrap(_G, 'RegisterCommand', 2)
wrap(_G, 'RegisterNUICallback', 2)
if type(Citizen) == 'table' then
  wrap(Citizen, 'CreateThread', 1)
  wrap(Citizen, 'CreateThreadNow', 1)
  wrap(Citizen, 'SetTimeout', 2)
end
