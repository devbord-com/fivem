-- Errors on the player's side: other resources report them through the exports; the server forwards them to devbord.
-- The client does not know the DSN and never talks to devbord itself.

---@class DevbordClientOptions
---@field level? 'fatal'|'error'|'warning'|'info'

---Reports an error (e.g. the result of xpcall(fn, debug.traceback)).
---@param err any the error message, optionally followed by a traceback
---@param opts DevbordClientOptions?
local function captureException(err, opts)
  local text = tostring(err)
  local first, rest = text:match('^([^\r\n]+)[\r\n]+(.+)$')
  TriggerServerEvent('devbord-errors:client', {
    message = (first or text):sub(1, 2000),
    trace = (rest or debug.traceback('', 2)):sub(1, 8000),
    level = opts and opts.level or 'error',
    resource = GetInvokingResource() or GetCurrentResourceName(),
  })
end

---Reports a message without an error.
---@param message string
---@param level? 'fatal'|'error'|'warning'|'info'
local function captureMessage(message, level)
  TriggerServerEvent('devbord-errors:client', {
    message = tostring(message):sub(1, 2000),
    level = level or 'info',
    resource = GetInvokingResource() or GetCurrentResourceName(),
  })
end

exports('captureException', captureException)
exports('captureMessage', captureMessage)
