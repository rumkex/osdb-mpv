if mp ~= nil then
    return
end

rpc = require 'xmlrpc.http'

OSDB_API = 'http://api.opensubtitles.org/xml-rpc'
USERAGENT = 'OSTestUserAgent'

LOGIN = ''
PASSWORD = ''

TMP = '/tmp/%s'
DL_COMMAND = 'wget -O- -q %s | gunzip > '..TMP

-- This file just performs RPC call to OpenSubtitles

osdb = {}
function osdb.login()
    local arguments = {}
    local ok, res = rpc.call(OSDB_API, 'LogIn', LOGIN, PASSWORD, 'en', USERAGENT)
    if not ok then
        error('Request failed.')
        return
    end
    if not res['status'] == '200 OK' then
        error('Request failed. ', res['status'])
        return
    end
    osdb.token = res['token']
end

function osdb.query(hash, size)
    local searchQuery = {
        {
            moviehash = hash, 
            moviebytesize = size, 
            sublanguageid = 'eng'
        }
    }
    local limit = {limit = 10}

    local ok, res = rpc.call(OSDB_API, 'SearchSubtitles', osdb.token, searchQuery, limit)
    if not ok then
        error('Request failed.')
        return
    end
    if not res['status'] == '200 OK' then
        error('Request failed. ', res['status'])
        return
    end
    return res['data'][1]
end

function osdb.download(subdata)
    if subdata == nil then
        error("invalid data")
        return
    end
    success = os.execute(string.format(DL_COMMAND, 
                                       subdata['SubDownloadLink'], 
                                       subdata['SubFileName']))
    if not success then
        return
    end
    return string.format(TMP, subdata['SubFileName'])
end

function osdb.logout()
    local arguments =  {
        ["token"] = token
    }
    local ok, res = rpc.call(OSDB_API, 'LogOut', osdb.token)
    if not ok then
        error('Request failed.')
        return
    end
    if not res['status'] == '200 OK' then
        error('Request failed. ', res['status'])
        return
    end
end

-- Main

hash = arg[1]
size = arg[2]
osdb.login()
local result = osdb.query(hash, size)
local subfile = osdb.download(result)
require('io').write(subfile)
osdb.logout()

