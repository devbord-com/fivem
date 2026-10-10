-- Collects the context on the player's side (location, street, vehicle, screenshot)
-- and sends everything to the server. The API key never reaches the client.

local function notify(msg)
  TriggerEvent('chat:addMessage', { color = { 120, 180, 255 }, multiline = true, args = { 'devbord', msg } })
end

RegisterNetEvent('devbord-bugreport:notify', function(msg)
  notify(msg)
end)

local function round(v)
  return math.floor(v * 100 + 0.5) / 100
end

local function collect()
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
  local street = GetStreetNameFromHashKey(s1)
  if s2 ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(s2) end
  local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
  local vehicle = nil
  local veh = GetVehiclePedIsIn(ped, false)
  if veh ~= 0 then
    vehicle = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
  end
  return {
    coords = { x = round(c.x), y = round(c.y), z = round(c.z), heading = round(GetEntityHeading(ped)) },
    street = street,
    zone = zone ~= 'NULL' and zone or nil,
    vehicle = vehicle,
    game_build = tostring(GetGameBuildNumber()),
  }
end

local function screenshotAvailable()
  return Config.Screenshot and GetResourceState('screenshot-basic') == 'started'
end

-- the server asks for the context after it has checked permission and cooldown
RegisterNetEvent('devbord-bugreport:collect', function(token)
  local data = collect()
  if screenshotAvailable() then
    exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = Config.ScreenshotQuality }, function(uri)
      data.screenshot = uri
      TriggerLatentServerEvent('devbord-bugreport:context', 200000, token, data)
    end)
  else
    TriggerLatentServerEvent('devbord-bugreport:context', 200000, token, data)
  end
end)

CreateThread(function()
  TriggerEvent('chat:addSuggestion', '/' .. Config.Command, Config.Messages.suggestion, {
    { name = Config.Messages.suggestionArg, help = Config.Messages.suggestionHelp },
  })
end)
