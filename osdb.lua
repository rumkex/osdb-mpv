require 'os'
require 'io'

msg = require 'mp.msg'
utils = require 'mp.utils'

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

function on_playback_started(event)
    local srcfile = mp.get_property('path')
    assert(srcfile ~= nil)
    local mhash, fsize = movieHash(srcfile)
    result = utils.subprocess({args = {'lua', 'osdb-rpc.lua', mhash, fsize}})
    subfile = result.stdout
    if subfile ~= nil then
        msg.info('Loading OpenSubtitles subtitle')
        mp.commandv('sub_add', subfile)
    else
        msg.error('No auto subtitle found')
    end
end

mp.register_event("file-loaded", on_playback_started)
