fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rps_multicharacter'
description 'Character selection with ped preview for rps_core'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

dependencies {
    'rps_core',
    'ox_lib',
    'oxmysql',
}
