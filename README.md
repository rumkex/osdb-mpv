# OSDb-mpv

OpenSubtitles automatic downloader script for [MPV](http://mpv.io/). Relies on LuaSocket, lua-xmlrpc and lua-zlib.

# Prerequisites

Obviously, you need to install MPV first.

*lua-xmlrpc* and its dependencies are available on LuaRocks:

    luarocks install luaxmlrpc lua-zlib

MPV is using Lua 5.2 by default, so it's recommended to use LuaRocks for the same version of Lua.

Alternatively, one can use distribution Lua packages (confirmed working on Ubuntu 16.04 and derivatives):

    sudo apt-get install lua-socket lua-xmlrpc lua-zlib
    # Currently, symlink is required to be able to use xmlrpc in Lua 5.2
    sudo ln -s /usr/share/lua/5.1/xmlrpc /usr/share/lua/5.2/xmlrpc

# Installation

Just drop *osdb.lua* into **~/.mpv/scripts** (or **~/.config/mpv/scripts**).

# Configuration

At the moment, this plugin has the following options:

    user=foo
    password=bar

Optional credentials to use with OpenSubtitles API - your login and password that you use on opensubtitles.org.

    autoLoadSubtitles=[yes|no]

Automatically load subtitles when a file is loaded. Default is 'no'.

    numSubtitles=10

Number of matching subtitles to query from OpenSubtitles. Default is 10. Maximum allowed is 500.

    language='eng'

Subtitle languages to search for. Default is 'eng'. Can be multiple values, comma-separated.

    autoFlagSubtitles=[yes|no]

Flag subtitles automatically when switching to the next subtitle suggestion. Default is 'no'.

You can either add those to MPV configuration file, for example:

    script-opts=osdb-autoLoadSubtitles=yes,osdb-numSubtitles=100

Or create a separate lua-settings/osdb.conf file with following contents:

    autoLoadSubtitles=yes
    numSubtitles=100
    user=foo
    password=bar

# Usage

If *autoLoadSubtitles* is enabled, subtitles will be found automatically when a file is loaded.

Otherwise, press **Ctrl+F** to search for subtitles.

To cycle through different subtitles found on OSDb, press **Ctrl+F** again.

To flag a subtitle, if it has invalid timings and/or designed for another release of the same movie, press **Ctrl+R**.

