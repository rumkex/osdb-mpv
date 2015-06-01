if mp == nil then
    print('Must be run inside MPV')
end

local rpc = require 'osdb-rpc'

local os = require 'os'
local io = require 'io'
local http = require 'socket.http'
local zlib = require 'zlib'
local ltn12 = require 'ltn12'

local msg = require 'mp.msg'
local utils = require 'mp.utils'

require 'mp.options'
-- Read options from {mpv_config_dir}/lua-settings/osdb.conf
local options = {
    autoLoadSubtitles = false,
    language = 'eng',
    autoFlagSubtitles = false
}
read_options(options, 'osdb')

TMP = '/tmp/%s'

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

-- Subtitle list cache
local subtitles = {}

function download_file(link, filename)
    assert(link and filename)

    local inflate = zlib.inflate()
    local decompress = function(chunk)
        if chunk ~= '' and chunk ~= nil then
            return inflate(chunk)
        else
            return chunk
        end
    end

    local subfile = string.format(TMP, filename)
    http.request {
        url = link,
        sink = ltn12.sink.chain(
            decompress,
            ltn12.sink.file(io.open(subfile, 'wb'))
        )
    }
    return subfile
end

function find_subtitles()
    mp.resume()
    if #subtitles == 0 then
        -- Refresh the subtitle list
        local srcfile = mp.get_property('path')
        assert(srcfile ~= nil)
        local mhash, fsize = movieHash(srcfile)
        msg.info('Querying OpenSubtitles database...')
        rpc.login()
        subtitles = rpc.query(mhash, fsize, options.language)
        rpc.logout()
    else
        -- Move to another subtitle
        mp.commandv('sub_remove', subtitles[1]._sid)
        if options.autoFlagSubtitles then
            flag_subtitle()
        end
        table.remove(subtitles, 1)
    end
    -- Load first subtitle
    local filename = download_file(subtitles[1].SubDownloadLink, 
                                   subtitles[1].SubFileName)
    mp.suspend()
    mp.commandv('sub_add', filename)
    mp.resume()
    -- Remember which track it is
    subtitles[1]._sid = mp.get_property('sid')
end

function flag_subtitle()
    mp.resume()
    if #subtitles > 0 then
        rpc.login()
        mp.osd_message("Subtitle suggestion reported as incorrect")
        rpc.report(subtitles[1])
        rpc.logout()
    end
end

mp.add_key_binding('Ctrl+r', 'osdb_report', flag_subtitle)
mp.add_key_binding('Ctrl+f', 'osdb_find_subtitles', find_subtitles)
mp.register_event('file-loaded', function (event) 
                                     if options.autoLoadSubtitles then 
                                        find_subtitles()
                                     end
                                 end)

