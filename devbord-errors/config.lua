-- devbord error tracking: settings
-- Do NOT put the DSN here, but in server.cfg (that way it stays on the server):
--   set devbord_dsn "https://<key>@your.domain/<project>"
--   set devbord_release "my-server@1.4.0"       # optional: the version of your scripts
--   set devbord_environment "production"        # optional
--   set devbord_monitor "fivem-server"          # optional: name of the monitor for the heartbeat (one per server)
Config = {}

-- capture script errors from the server console automatically (all resources)
Config.CaptureConsole = true

-- accept errors that players (clients) send in through the export
Config.AcceptClient = true

-- at most this many errors per minute to devbord (the rest is dropped)
Config.MaxPerMinute = 60

-- at most this many errors per minute per player
Config.ClientPerMinute = 5

-- send the same error only once within this number of seconds
Config.DedupeSeconds = 10

-- which identifier identifies the player (never the IP address); false = send no player
Config.PlayerIdentifier = 'license'

-- resources whose errors you do not want (names)
Config.IgnoreResources = {}

-- name of the server as it appears with the error (empty = sv_hostname)
Config.ServerName = ''

-- send along with every error what the server is running: framework, version of the resource, artifact, game build, number of players
Config.Context = true

-- your own tags on every error, e.g. { region = 'eu', server = 'rp-1' }
Config.Tags = {}

-- the server checks in with a monitor in devbord; if the check-in stops coming, you get an issue "Server stopped reporting"
Config.Heartbeat = true

-- how often, in minutes, the server checks in
Config.HeartbeatMinutes = 1

-- how many minutes late a check-in may be (enough room for a restart); applies when the monitor is created
Config.HeartbeatMargin = 5
