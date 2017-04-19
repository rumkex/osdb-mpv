if mp == nil then
    print('Must be run inside MPV')
end

local rpc = require 'xmlrpc.http'
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
    tempFolder = '/tmp',
    autoLoadSubtitles = false,
    numSubtitles = 10,
    language = 'eng',
    autoFlagSubtitles = false,
    useHashSearch = true,
    useFilenameSearch = true,
    user = '',
    password = ''
}
read_options(options, 'osdb')


-- This is for performing RPC calls to OpenSubtitles
local osdb = {}

osdb.API = 'http://api.opensubtitles.org/xml-rpc'
osdb.USERAGENT = 'osdb-mpv v1'

function osdb.check(ok, res)
    if not ok then
        error('Request failed.')
    end
    if not res.status == '200 OK' then
        error('Request failed. ', res.status)
    end
end

function osdb.login(user, password)
    local ok, res = rpc.call(osdb.API, 'LogIn', user,
                             password, 'en', osdb.USERAGENT)
    osdb.check(ok, res)
    osdb.token = res.token
end

function osdb.logout()
    assert(osdb.token)
    local ok, res = rpc.call(osdb.API, 'LogOut', osdb.token)
    osdb.check(ok, res)
end

function osdb.query(search_query, nsubtitles)
    assert(osdb.token)
    local limit = {limit = nsubtitles}

    local ok, res = rpc.call(osdb.API, 'SearchSubtitles',
                             osdb.token, search_query, limit)
    osdb.check(ok, res)
    if res.data == false then
        error('No subtitles found in OSDb')
    end
    return res.data
end

function osdb.report(subdata)
    assert(osdb.token)
    assert(subdata)
    local ok, res = rpc.call(osdb.API, 'ReportWrongMovieHash',
                             osdb.token, subdata.IDSubMovieFile)
    osdb.check(ok, res)
end

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

    local subfile = string.format(options.tempFolder..'/%s', filename)
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
        mp.osd_message("Searching for subtitles...")
        local searchQuery = {}
        if options.useHashSearch then
            local ok, mhash, fsize = pcall(movieHash, srcfile)
            if ok then
                table.insert(searchQuery,
                {
                    moviehash = mhash,
                    moviebytesize = fsize,
                    sublanguageid = options.language
                })
            else
                msg.warn("Movie hash couldn't be computed")
            end
        end
        if options.useFilenameSearch then
            local _, basename = utils.split_path(srcfile)
            table.insert(searchQuery,
            {
                query = basename,
                sublanguageid = options.language
            })
        end
        osdb.login(options.user, options.password)
        subtitles = osdb.query(searchQuery, options.numSubtitles)
        current_subtitle = 1
        osdb.logout()
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
    -- Load current subtitle
    local sub = subtitles[current_subtitle]
    mp.osd_message(string.format(
        "[%d/%d] Downloading subtitle…\n%s",
        current_subtitle, #subtitles, sub.SubFileName
    ))
    local filename = download_file(sub.SubDownloadLink,
                                   sub.SubFileName)
    mp.commandv('sub_add', filename)
    mp.osd_message(string.format(
        "[%d/%d] Using subtitle (matched by %s)\n%s",
        current_subtitle, #subtitles, sub.MatchedBy, sub.SubFileName
    ))
    -- Remember which track it is
    subtitles[current_subtitle]._sid = mp.get_property('sid')
end

function flag_subtitle()
    if #subtitles > 0 and subtitles[current_subtitle].MatchedBy == 'moviehash' then
        osdb.login(options.user, options.password)
        mp.osd_message("Subtitle suggestion reported as incorrect")
        osdb.report(subtitles[current_subtitle])
        osdb.logout()
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

