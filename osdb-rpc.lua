if mp ~= nil then
-- lua-xmlrpc is broken inside MPV for some reason
    return
end

local rpc = require 'xmlrpc.http'

OSDB_API = 'http://api.opensubtitles.org/xml-rpc'
USERAGENT = 'OSTestUserAgent'

LOGIN = ''
PASSWORD = ''

MAX_SUBTITLES = 50

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
    local limit = {limit = MAX_SUBTITLES}

    local ok, res = rpc.call(OSDB_API, 'SearchSubtitles', osdb.token, searchQuery, limit)
    osdb.check(ok, res)
    if res['data'] == false then
        error('Subtitle not found in OSDb')
    end
    return res['data']
end

-- Main

hash = arg[1]
size = arg[2]
lang = arg[3]
osdb.login()
local result = osdb.query(hash, size, lang)
osdb.logout()

for i, data in pairs(result) do
    print(data['IDSubMovieFile'], data['SubDownloadLink'], data['SubFileName'])
end
