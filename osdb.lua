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
    numSubtitles = 10,
    language = 'eng',
    autoFlagSubtitles = false,
    user = '',
    password = ''
}
read_options(options, 'osdb')

local TMP = '/tmp/%s'

-- Movie hash function for OSDB, courtesy of 
-- http://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes
function movieHash(fileName)
        local fil = io.open(fileName, "rb")
        if fil == nil then
            error("Can't open file")
        end
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
local current_subtitle = 0

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
    if #subtitles == 0 then
        -- Refresh the subtitle list
        local srcfile = mp.get_property('path')
        assert(srcfile ~= nil)
        local ok, mhash, fsize = pcall(movieHash, srcfile)
        if not ok then
            msg.warn("Movie hash couldn't be computed")
            return
        end
        mp.osd_message("Searching for subtitles...")
        rpc.login(options.user, options.password)
        subtitles = rpc.query(options.numSubtitles,
                              mhash, fsize,
                              options.language)
        current_subtitle = 1
        rpc.logout()
    else
        -- Move to the next subtitle
        if subtitles[current_subtitle]._sid ~= nil then
            mp.commandv('sub_remove', subtitles[current_subtitle]._sid)
            if options.autoFlagSubtitles then
                flag_subtitle()
            end
        end
        current_subtitle = current_subtitle + 1
        if current_subtitle > #subtitles then
            current_subtitle = 1
        end
    end
    if #subtitles == 0 then
        mp.osd_message("No subtitles found")
        return
    end
    -- Load first subtitle
    local filename = download_file(subtitles[current_subtitle].SubDownloadLink,
                                   subtitles[current_subtitle].SubFileName)
    mp.commandv('sub_add', filename)
    mp.osd_message("Using subtitles "..current_subtitle.."/"..#subtitles)
    -- Remember which track it is
    subtitles[current_subtitle]._sid = mp.get_property('sid')
end

function flag_subtitle()
    if #subtitles > 0 then
        rpc.login()
        mp.osd_message("Subtitle suggestion reported as incorrect")
        rpc.report(subtitles[current_subtitle])
        rpc.logout()
    end
end

function catch(callback, ...)
    xpcall(
        callback,
        function(err)
            msg.warn(debug.traceback())
            msg.fatal(err)
            mp.osd_message("Error: " .. err)
        end,
        ...
    )
end

mp.add_key_binding('Ctrl+r', 'osdb_report', function() catch(flag_subtitle) end)
mp.add_key_binding('Ctrl+f', 'osdb_find_subtitles', function() catch(find_subtitles) end)
mp.register_event('file-loaded', function (event) 
                                     -- Reset the cache
                                     subtitles = {}
                                     if options.autoLoadSubtitles then 
                                        catch(find_subtitles)
                                     end
                                 end)

