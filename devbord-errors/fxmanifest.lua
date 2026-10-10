fx_version 'cerulean'
games { 'gta5', 'rdr3' }
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'devbord-errors'
description 'Script errors from the server and from players to the error tracking of devbord, with a server heartbeat'
author 'The Remedy'
version '1.2.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

-- other resources load this as their first client script to have their client errors caught
file 'capture.lua'
