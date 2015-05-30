# OSDb-mpv
OpenSubtitles automatic downloader script for [MPV](http://mpv.io/). Relies on LuaSocket, lua-xmlrpc and lua-zlib.

# Prerequisites

Obviously, you need to install MPV first

On latest Debian/Ubuntu, you also need the following packages:

    sudo apt-get install lua5.1 lua-xmlrpc lua-zlib

LuaRocks and LuaDist don't have *lua-xmlrpc*, but you can get it [from source repository](https://github.com/timn/lua-xmlrpc).

# Installation

Just drop *osdb.lua* and *osdb-rpc.lua* into **~/.mpv/scripts** (or **~/.config/mpv/scripts**).

# Configuration

At the moment, this plugin has just a single option:
    autoLoadSubtitles=[yes|no]
It automatically loads subtitles when a file is loaded. Default is 'no'.

You can either add it to MPV configuration file:
    script-opts=osdb-autoLoadSubtitles=yes
Or create a separate lua-settings/osdb.conf file with following contents:
    autoLoadSubtitles=yes
    
# Usage

If *autoLoadSubtitles* is enabled, subtitles will be found automatically when a file is loaded.

Otherwise, press **Ctrl+F** to search for subtitles.

To cycle through different subtitles found on OSDb, press **Ctrl+F** again.

