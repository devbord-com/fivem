-- devbord bug reports: settings
-- Do NOT put the API key and the address here, but in server.cfg (that way they never reach players):
--   set devbord_url "https://devbord.com"
--   set devbord_api_key "db_xxxxxxxx_..."
--   set devbord_board_id "12"      # only needed with a workspace key
Config = {}

-- language of the fixed words on the card ("Player", "Location"): 'en' or 'nl'
Config.Locale = 'en'

-- chat command, e.g. /bug The garage door at the PD does not open
Config.Command = 'bug'

-- list on the board the reports go to (name or ID); empty = first list
Config.List = 'Bugs'

-- label on the card (created if it does not exist yet); false = no label
Config.Label = 'Bug'

-- send a screenshot along (requires the resource "screenshot-basic")
Config.Screenshot = true
Config.ScreenshotQuality = 0.6 -- 0.1 to 1.0 (jpg)

-- cooldown per player between two reports (seconds)
Config.Cooldown = 120

-- minimum length of the description
Config.MinLength = 8

-- which identifiers are sent along (never the IP address). Leave empty = no identifiers.
Config.Identifiers = { 'license', 'discord' }

-- name of the server as it appears on the card (empty = sv_hostname)
Config.ServerName = ''

-- ACE permission needed to report; nil = everyone
-- e.g. 'devbord.bug' and in server.cfg: add_ace group.admin devbord.bug allow
Config.Permission = nil

-- tell the player that their report was fixed (the card is completed on devbord); if they are not online,
-- they get the message on their next visit
Config.NotifyFixed = true
Config.StatusInterval = 5 -- how often, in minutes, the server asks for the status
Config.FixedDays = 30     -- how long a report stays tracked

Config.Messages = {
  usage = 'Usage: /bug <description of the problem>',
  tooShort = 'Please describe the bug in a bit more detail.',
  cooldown = 'Please wait before you report another bug (%d s).',
  noPermission = 'You are not allowed to report bugs.',
  sending = 'Sending bug report…',
  sent = 'Thanks! Your report is on devbord as #%s.',
  sentDuplicate = 'Thanks! This bug was already reported (#%s); your report was added to it.',
  fixed = 'Good news: your bug report #%s was fixed.',
  suggestion = 'Report a bug to the dev team',
  suggestionArg = 'description',
  suggestionHelp = 'What went wrong, and what did you expect?',
  failed = 'Sending the bug report failed. Try again later.',
  notConfigured = 'Bug reports are not set up on this server yet.',
}
