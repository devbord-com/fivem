# devbord-bugreport

FiveM resource that lets players report bugs with `/bug <description>`. Every report becomes a card on devbord with:

- the description (first line = title)
- player name, server ID and the chosen identifiers (`license` and `discord` by default, **never the IP address**)
- location as `vector3(x, y, z)` + heading, street and zone
- vehicle (if the player is in a vehicle), server name and game build
- a screenshot as cover (if `screenshot-basic` is running)
- the label **Bug** (created if it does not exist yet)

When the card is completed on devbord, the player gets a message in the game that their report was fixed (right away if
they are online, otherwise on their next visit).

## Install

1. In devbord, create an **API key with the "Report only" scope** on the board for bugs and pick the list the reports go
   to (board menu › Integrations › API keys). Such a key cannot read or change anything.
   A key with write access or a workspace key works too (with a workspace key, set `devbord_board_id`); then
   `Config.List` decides the list. A "Report only" key needs the Standard plan or higher
   (50 reports a month, no monthly limit with Premium); the other keys need Premium.
2. Copy this folder to `resources/[devbord]/devbord-bugreport`.
3. Add to `server.cfg`:

   ```cfg
   ensure screenshot-basic        # optional, for screenshots
   ensure devbord-bugreport
   set devbord_url "https://devbord.com"
   set devbord_api_key "db_xxxxxxxx_..."
   # set devbord_board_id "12"    # only with a workspace key
   ```

   Do **not** put the key in `config.lua`; convars stay on the server and never reach players.
4. Adjust `config.lua` as you like: command, language, list, label, cooldown, ACE permission, which identifiers are
   sent along and whether players are told that their report was fixed.

## Reporting from another resource

```lua
-- server-side; the player gets no chat message, the card does get their location and screenshot
exports['devbord-bugreport']:report(source, 'Vehicle spawns under the map', {
  title = 'Garage: vehicle under the map',   -- optional
  fingerprint = 'garage:spawn-under-map',    -- reports with the same value are collected on one card
  label = 'Bug',                             -- or false for no label
})
```

With a `fingerprint`, the second report does not create a new card: it is added as a comment on the first and the
counter on the card goes up. If that card is completed and the bug comes back, a new card is created.

## Security

- The API key is on the server only; the client sends nothing but location and screenshot.
- Every report has a one-time token, so players cannot forge or replay reports through events.
- Cooldown per player (2 minutes by default) and a limit per key on devbord (120 reports per hour by default,
  adjustable on the key).
- To find players again, the server stores the license and the receipt of each report (in the KVP storage of
  the resource), for at most `Config.FixedDays` days. The license only goes to devbord if it is in `Config.Identifiers`.
- devbord checks that the screenshot really is a jpg/png/webp and sanitises all text.
