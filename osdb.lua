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
    osdDelayLong = 30,
    osdDelayShort = -1,
    user = '',
    password = ''
}
read_options(options, 'osdb')


-- This is for performing RPC calls to OpenSubtitles
local osdb = {}

osdb.API = 'http://api.opensubtitles.org/xml-rpc'
osdb.USERAGENT = 'osdb-mpv v1'

function osdb.rpc(...)
    local args = {...}

    for i, item in pairs(args) do
        args[i] = osdb.xml_escape(item)
    end

    local ok, res = rpc.call(osdb.API, table.unpack(args))

    if not ok then
        error('Request failed.')
    elseif res.status ~= '200 OK' then
        error('Request failed: ' .. res.status)
    end

    return res
end

function osdb.login(user, password)
    local res = osdb.rpc('LogIn', user, password, 'en', osdb.USERAGENT)
    osdb.token = res.token
end

function osdb.logout()
    assert(osdb.token)
    osdb.rpc('LogOut', osdb.token)
end

function osdb.query(search_query, nsubtitles)
    assert(osdb.token)
    local limit = {limit = nsubtitles}

    local res = osdb.rpc('SearchSubtitles', osdb.token, search_query, limit)
    if res.data == false then
        error('No subtitles found in OSDb')
    end
    return res.data
end

function osdb.report(subdata)
    assert(osdb.token)
    assert(subdata)
    osdb.rpc('ReportWrongMovieHash', osdb.token, subdata.IDSubMovieFile)
end

function osdb.xml_escape(val)
    if type(val) == 'string' then
        return val:gsub('%&', '&amp;'):gsub('%<', '&lt;'):gsub('%>', '&gt;')
    elseif type(val) == 'table' then
        local conv = {}
        for k, v in pairs(val) do
            conv[k] = osdb.xml_escape(v)
        end
        return conv
    else
        return val
    end
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

function download(subtitle)
    assert(subtitle.SubDownloadLink and subtitle.SubFileName)

    local inflate = zlib.inflate()
    local decompress = function(chunk)
        if chunk ~= '' and chunk ~= nil then
            return inflate(chunk)
        else
            return chunk
        end
    end

    local subfile = string.format(options.tempFolder..'/%s', subtitle.SubFileName)
    http.request {
        url = subtitle.SubDownloadLink,
        sink = ltn12.sink.chain(
            decompress,
            ltn12.sink.file(io.open(subfile, 'wb'))
        )
    }
    return subfile
end

-- Subtitle list cache
local subtitles = {}

function subtitles.set(self, list)
    self.count = #list
    self.list = list
    self.current = nil
    self.idx = nil

    for _, sub in pairs(list) do
	sub.download = download
    end
end

function subtitles.next(self)
    self.idx = next(self.list, self.idx)
    self.current = self.list[self.idx]
end

function fetch_list()
        local srcfile = mp.get_property('path')
        assert(srcfile ~= nil)
        mp.osd_message("Searching for subtitles...", options.osdDelayLong)
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
        subtitles:set(osdb.query(searchQuery, options.numSubtitles))

        if subtitles.count == 0 then
            mp.osd_message("No subtitles found", options.osdDelayShort)
        end
        osdb.logout()
end

function rotate_subtitles()
    if subtitles.count == 0 then
        -- Refresh the subtitle list
        fetch_list()
    end

    -- Remove previous subtitle track, if possible
    if subtitles.current ~= nil and subtitles.current._sid ~= nil then
        mp.commandv('sub_remove', subtitles.current._sid)
        if options.autoFlagSubtitles then
            flag_subtitle()
        end
    end

    -- Move to the next subtitle
    subtitles:next()

    -- If at the end of the list (or no subtitles found), don't do anything
    if subtitles.current == nil then
        return
    end

    -- Load current subtitle
    mp.osd_message(string.format(
        "[%d/%d] Downloading subtitle…\n%s",
        subtitles.idx, subtitles.count, subtitles.current.SubFileName
    ), options.osdDelayLong)
    local filename = subtitles.current:download()
    mp.commandv('sub_add', filename)
    mp.osd_message(string.format(
        "[%d/%d] Using subtitle (matched by %s)\n%s",
        subtitles.idx, subtitles.count,
        subtitles.current.MatchedBy, subtitles.current.SubFileName
    ), options.osdDelayShort)
    -- Remember which track it is
    subtitles.current._sid = mp.get_property('sid')
end

function flag_subtitle()
    if subtitles.current ~= nil and subtitles.current.MatchedBy == 'moviehash' then
        osdb.login(options.user, options.password)
        mp.osd_message("Subtitle suggestion reported as incorrect",
                       options.osdDelayShort)
        osdb.report(subtitles.current)
        osdb.logout()
    end
end

function catch(callback, ...)
    xpcall(
        callback,
        function(err)
            msg.warn(debug.traceback())
            msg.fatal(err)
            mp.osd_message("Error: " .. err, options.osdDelayShort)
        end,
        ...
    )
end

mp.add_key_binding('Ctrl+r', 'osdb_report', function() catch(flag_subtitle) end)
mp.add_key_binding('Ctrl+f', 'osdb_find_subtitles', function() catch(rotate_subtitles) end)
mp.register_event('file-loaded', function (event)
                                     -- Reset the cache
                                     subtitles:set({})
                                     if options.autoLoadSubtitles then
                                        catch(rotate_subtitles)
                                     end
                                 end)

