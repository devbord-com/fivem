# devbord for FiveM and RedM

Two resources that connect a FiveM or RedM server to [devbord](https://devbord.com). They work on their own; install
one or both.

| Resource | What it does |
|---|---|
| [devbord-errors](devbord-errors) | Sends script errors of the server and of players to error tracking, with the framework, the resource and its version. Reports a heartbeat, so devbord tells you when the server stops. FiveM and RedM. |
| [devbord-bugreport](devbord-bugreport) | Players type `/bug <description>`; the report becomes a card with their position, vehicle and a screenshot, and they hear it in the game when the bug is fixed. FiveM. |

## Install

Download the latest release, copy the folders you want into `resources/[devbord]/` and follow the README of each
resource. Keys go in `server.cfg`, never in a file that is sent to players.

## Writing your own

The protocol these resources use is described in [devbord-com/integrations](https://github.com/devbord-com/integrations),
with a tool that checks what an integration sends.
