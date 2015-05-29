if mp ~= nil then
-- lua-xmlrpc is broken inside MPV for some reason
    return
end

local rpc = require 'xmlrpc.http'
local io = require 'io'
local http = require 'socket.http'
local zlib = require 'zlib'
local ltn12 = require 'ltn12'

OSDB_API = 'http://api.opensubtitles.org/xml-rpc'
USERAGENT = 'OSTestUserAgent'

LOGIN = ''
PASSWORD = ''

TMP = '/tmp/%s'
DL_COMMAND = 'wget -O- -q %s | gunzip > '..TMP

-- This file just performs RPC call to OpenSubtitles

osdb = {}
function osdb.check(ok, res)
    if not ok then
        error('Request failed.')
    end
    if not res['status'] == '200 OK' then
        error('Request failed. ', res['status'])
    end
end

function osdb.login()
    local arguments = {}
    local ok, res = rpc.call(OSDB_API, 'LogIn', LOGIN, PASSWORD, 'en', USERAGENT)
    osdb.check(ok, res)
    osdb.token = res['token']
end

function osdb.logout()
    local arguments =  {
        ["token"] = token
    }
    local ok, res = rpc.call(OSDB_API, 'LogOut', osdb.token)
    osdb.check(ok, res)
end

function osdb.query(hash, size, language)
    local searchQuery = {
        {
            moviehash = hash, 
            moviebytesize = size, 
            sublanguageid = language
        }
    }
    local limit = {limit = 10}

    local ok, res = rpc.call(OSDB_API, 'SearchSubtitles', osdb.token, searchQuery, limit)
    osdb.check(ok, res)
    if res['data'] == false then
        error('Subtitle not found in OSDb')
    end
    return res['data'][1]
end

function osdb.download(subdata)
    if subdata == nil then
        error("invalid data")
        return
    end

    inflate = zlib.inflate()
    decompress = function(chunk)
        if chunk ~= '' and chunk ~= nil then
            return inflate(chunk)
        else
            return chunk
        end
    end

    subfile = string.format(TMP, subdata['SubFileName'])
    http.request {
        url = subdata['SubDownloadLink'],
        sink = ltn12.sink.chain(
            decompress,
            ltn12.sink.file(io.open(subfile, 'wb'))
        )
    }
    return subfile
end


-- Main

hash = arg[1]
size = arg[2]
lang = arg[3]
osdb.login()
local result = osdb.query(hash, size, lang)
local subfile = osdb.download(result)
require('io').write(subfile)
osdb.logout()
