if mp == nil then
    print('Must be run inside MPV')
end

require 'os'
require 'io'

msg = require 'mp.msg'
utils = require 'mp.utils'

require 'mp.options'
-- Read options from {mpv_config_dir}/lua-settings/osdb.conf
local options = {
    autoLoadSubtitles = false
}
read_options(options, 'osdb')

-- Find osdb-rpc.lua
for path in string.gmatch(package.path, "[^;]+") do
-- Last path should be {mpv_config_dir}/scripts/
    scriptsPath = utils.split_path(path)
end
OSDB_RPC_PATH = scriptsPath..'osdb-rpc.lua'
msg.debug('osdb-rpc.lua location: '..OSDB_RPC_PATH)

-- Movie hash function for OSDB, courtesy of 
-- http://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes
function movieHash(fileName)
        local fil = io.open(fileName, "rb")
        local lo,hi=0,0
        for i=1,8192 do
                local a,b,c,d = fil:read(4):byte(1,4)
                lo = lo + a + b*256 + c*65536 + d*16777216
                a,b,c,d = fil:read(4):byte(1,4)
                hi = hi + a + b*256 + c*65536 + d*16777216
                while lo>=4294967296 do
                        lo = lo-4294967296
                        hi = hi+1
                end
                while hi>=4294967296 do
                        hi = hi-4294967296
                end
        end
        local size = fil:seek("end", -65536) + 65536
        for i=1,8192 do
                local a,b,c,d = fil:read(4):byte(1,4)
                lo = lo + a + b*256 + c*65536 + d*16777216
                a,b,c,d = fil:read(4):byte(1,4)
                hi = hi + a + b*256 + c*65536 + d*16777216
                while lo>=4294967296 do
                        lo = lo-4294967296
                        hi = hi+1
                end
                while hi>=4294967296 do
                        hi = hi-4294967296
                end
        end
        lo = lo + size
                while lo>=4294967296 do
                        lo = lo-4294967296
                        hi = hi+1
                end
                while hi>=4294967296 do
                        hi = hi-4294967296
                end
        fil:close()
        return string.format("%08x%08x", hi,lo), size
end

function find_subtitles()
    local srcfile = mp.get_property('path')
    assert(srcfile ~= nil)
    local mhash, fsize = movieHash(srcfile)
    msg.info('Loading OpenSubtitles subtitle...')
    result = utils.subprocess({args = {'lua', OSDB_RPC_PATH, mhash, fsize}})
    if result.status == 0 then
        mp.commandv('sub_add', result.stdout)
    else
        msg.error('Failure.')
    end
end

mp.add_key_binding('Ctrl+f', 'osdb_find_subtitles', find_subtitles)
mp.register_event('file-loaded', function (event) 
                                     if options.autoLoadSubtitles then 
                                        find_subtitles()
                                     end
                                 end)

