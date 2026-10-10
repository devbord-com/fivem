# devbord-errors

FiveM resource that sends script errors to the error tracking of devbord. Identical errors form one issue there, with
the number of occurrences, the affected players and the resource; with a rule under Automation it becomes a card by itself.

- **Server console**: every `SCRIPT ERROR` of every resource, with the stack.
- **Exports** (server and client): `captureException` and `captureMessage`, for errors you catch yourself.
- **Players**: errors on the client go through the server; the DSN never reaches players. Resources that load
  `capture.lua` have their uncaught client errors sent by themselves.
- **Heartbeat**: the server checks in with a monitor every minute. If the check-in stops coming, devbord turns it into
  an issue; once the server runs again, that issue resolves by itself.
- **Context**: with every error the framework (ESX, QBCore, Qbox, ox, ND, VORP, RSG), the version of the resource, the
  artifact, the game build and the number of players, so you can filter issues on them.

Works on FiveM and on RedM.

## Install

1. In devbord, create a key in the project under **Errors › Set up** and copy the DSN.
2. Copy this folder to `resources/[devbord]/devbord-errors`.
3. Add to `server.cfg`:

   ```cfg
   set devbord_dsn "https://<key>@your.domain/<project>"
   set devbord_release "my-server@1.4.0"     # optional
   set devbord_monitor "rp-1"                # optional: name of the monitor, one per server
   ensure devbord-errors
   ```

   Put `devbord-errors` before your other resources, so errors during startup come in as well.
4. Adjust `config.lua` as you like: limits per minute, which identifier identifies the player, resources you
   ignore, your own tags and the heartbeat.

## Heartbeat

The first check-in creates a monitor in devbord under **Errors › Monitors** with the name from `devbord_monitor`
(`fivem-server` by default). Give every server that sends to the same project its own name. The monitor expects a
check-in every minute, with a margin of 5 minutes, so a scheduled restart does not cause an issue; if your restart takes
longer, raise `Config.HeartbeatMargin` before the first start or adjust the margin later in devbord. Check-ins do not
count towards the monthly total. Set `Config.Heartbeat = false` to turn the heartbeat off.

## Reporting errors yourself

```lua
local ok, err = xpcall(function()
  doSomething()
end, debug.traceback)
if not ok then exports['devbord-errors']:captureException(err) end

exports['devbord-errors']:captureMessage('Database slow: 4.2 s', 'warning')
```

The same two exports work on the client.

## Errors on the client

Every script error on the server reaches devbord without any change to your resources: nil values, failed calls,
errors in event handlers, of every resource. A client has no console the server can listen to, so there a resource has
to opt in. Add this as the **first** client script in the `fxmanifest.lua` of each resource whose client errors you want:

```lua
client_script '@devbord-errors/capture.lua'
```

and start `devbord-errors` before those resources. From then on an error in one of its threads, event handlers,
commands, NUI callbacks or timers is sent to devbord with its stack and the player, and still shows in the F8 console.
A client sends at most 5 errors per minute and the same error once per 10 seconds.

Not caught: an error at the top level of a file while it loads, and an error inside a function another resource calls
through an export. This works for Lua resources only.

## Security and limits

- The DSN is only in a convar on the server.
- At most 5 errors per minute per player and at most 60 per minute in total; the same error within 10 seconds is sent once.
- Of the player, the name and one identifier are sent along (`license` by default), never the IP address. Set `Config.PlayerIdentifier = false` to send no player.

## Status

The protocol (the requests to devbord, including the heartbeat and what `capture.lua` sends) has been tested against devbord itself, with the resource
run outside FXServer (`conformance/fivem.lua` in [devbord-com/integrations](https://github.com/devbord-com/integrations)). Capturing from the server console relies on
`RegisterConsoleListener` and on the format of the error lines of FXServer; that has not been checked on a running FiveM
server yet, and neither has loading `capture.lua` from another resource. If you see errors in the console that do not show up in devbord, report the exact lines.
