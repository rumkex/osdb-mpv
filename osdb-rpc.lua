local rpc = require 'xmlrpc.http'

-- This module just performs RPC call to OpenSubtitles

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

function osdb.query(nsubtitles, search_query)
    assert(osdb.token)
    assert(search_query)
    local limit = {limit = nsubtitles}

    local ok, res = rpc.call(osdb.API, 'SearchSubtitles', 
                             osdb.token, search_query, limit)
    osdb.check(ok, res)
    if res.data == false then
        error('No subtitles found in OSDb')
    end
    return res.data
end

function osdb.query_hash(nsubtitles, language, hash, size)
    assert(language and hash and size)
    return osdb.query(nsubtitles, {
        {
            moviehash = hash,
            moviebytesize = size,
            sublanguageid = language
        }
    })
end

function osdb.query_text(nsubtitles, language, query)
    assert(language and query)
    return osdb.query(nsubtitles, {
        {
            query = query,
            sublanguageid = language
        }
    })
end

function osdb.report(subdata)
    assert(osdb.token)
    assert(subdata)
    local ok, res = rpc.call(osdb.API, 'ReportWrongMovieHash', 
                             osdb.token, subdata.IDSubMovieFile)
    osdb.check(ok, res)
end

return osdb

