-- Self-update support for the Kindle Click plugin.
--
-- The plugin lives in a public GitHub repository, so the cheapest reliable
-- updater is a plain file fetch: read the remote _meta.lua to learn the
-- version, then download the file list from the repository root. Nothing is
-- replaced until every file has arrived, so an interrupted download leaves
-- the installed version untouched.

local Log = require("kindleclick_log")

local Update = {}

Update.REPO = "freeadf9b/kindleclick.koplugin"
Update.BRANCH = "main"
Update.VERSION_FILE = "_meta.lua"
Update.MANIFEST_FILE = "manifest.txt"

-- Used when the repository has no manifest yet (older installs updating to a
-- release that predates it).
Update.FILES = {
    "_meta.lua",
    "main.lua",
    "kindleclick_backend.lua",
    "kindleclick_bluetooth.lua",
    "kindleclick_diagnostics.lua",
    "kindleclick_icons.lua",
    "kindleclick_log.lua",
    "kindleclick_update.lua",
    "kindleclick_zenos.lua",
    "manifest.txt",
    "README.md",
    "fonts/kindleclick-icons.kfont",
    "icons/kindleclick.svg",
}

local function plugin_base(url)
    return url .. "/kindleclick.koplugin/"
end

-- Tags are named "v<version>". Until a version is known we ask jsDelivr for
-- "@latest", which resolves the newest release tag: the default branch of the
-- repository is not guaranteed to be up to date.
local function ref_for(version)
    if version and tostring(version) ~= "" then
        return "v" .. tostring(version)
    end
    return "latest"
end

local function mirrors(version)
    -- Ordered by how reachable they usually are from mainland China. All of
    -- these speak the jsDelivr "@ref" URL scheme, so "@latest" works until the
    -- real version is known; the raw mirrors need an explicit ref and are only
    -- added afterwards.
    local ref = ref_for(version)
    local prefix = "/gh/" .. Update.REPO .. "@" .. ref
    local list = {
        plugin_base("https://fastly.jsdelivr.net" .. prefix),
        plugin_base("https://gcore.jsdelivr.net" .. prefix),
        plugin_base("https://jsd.onmicrosoft.cn" .. prefix),
        plugin_base("https://jsd.cdn.zzko.cn" .. prefix),
        plugin_base("https://cdn.jsdelivr.net" .. prefix),
    }
    if version then
        local raw = "https://raw.githubusercontent.com/" .. Update.REPO .. "/" .. ref
        list[#list + 1] = "https://ghfast.top/" .. raw .. "/kindleclick.koplugin/"
        list[#list + 1] = "https://gh-proxy.com/" .. raw .. "/kindleclick.koplugin/"
        list[#list + 1] = "https://raw.gitmirror.com/" .. Update.REPO .. "/" .. ref .. "/kindleclick.koplugin/"
        list[#list + 1] = plugin_base(raw)
    end
    return list
end

-- Blocking GET through LuaSocket. The Turbo-based HTTPClient threw an
-- exception on some Kindle builds (the updater only logged "request_failed"),
-- and a plain socket request works everywhere KOReader runs. The caller shows
-- a "checking" toast first, so a short freeze here is acceptable.
local function fetch(url, callback)
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    if not ok_ltn12 then
        callback(false, nil, "no_ltn12")
        return
    end
    local ok_http, http = pcall(require, "socket.http")
    local ok_ssl, https = pcall(require, "ssl.https")
    if not ok_http and not ok_ssl then
        callback(false, nil, "no_luasocket")
        return
    end
    http.TIMEOUT = 30
    if ok_ssl then https.TIMEOUT = 30 end
    local sink = {}
    local request = {
        url = url,
        method = "GET",
        sink = ltn12.sink.table(sink),
        headers = { ["User-Agent"] = "kindleclick-koplugin" },
    }
    local ok, first, second
    if ok_ssl and url:match("^https://") then
        ok, first, second = pcall(https.request, request)
    else
        ok, first, second = pcall(http.request, request)
    end
    if not ok then
        callback(false, nil, "request_failed: " .. tostring(first))
        return
    end
    -- LuaSocket returns (1, status_code, headers, status_line) on success and
    -- (nil, error_message) on a transport failure. The status code is the
    -- second value, not the first.
    if first ~= 1 then
        callback(false, nil, "request_failed: " .. tostring(second or first))
        return
    end
    local status = tonumber(second)
    if status == 200 then
        callback(true, table.concat(sink))
    else
        callback(false, nil, "http_" .. tostring(status))
    end
end

-- jsDelivr caches files for up to 12 hours, which would hide a fresh push.
-- Appending a cache key makes every fetch a distinct URL, so the CDN asks
-- GitHub instead of serving its cached copy.
local function fetch_first(path, callback, cache_bust, version)
    local urls = mirrors(version)
    local index = 1
    local last_err
    local function next_mirror()
        if index > #urls then
            callback(false, nil, last_err or "unreachable")
            return
        end
        local url = urls[index] .. path
        index = index + 1
        if cache_bust then
            url = url .. "?kc=" .. tostring(cache_bust)
        end
        fetch(url, function(ok, body, err)
            if ok then
                callback(true, body)
            else
                last_err = err or "unknown"
                Log.write("update", "mirror failed: " .. url .. " -> " .. tostring(last_err))
                next_mirror()
            end
        end)
    end
    next_mirror()
end

local function split_version(version)
    local parts = {}
    for number in tostring(version or ""):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(number) or 0
    end
    return parts
end

function Update.isNewer(remote, local_version)
    local a = split_version(remote)
    local b = split_version(local_version)
    for i = 1, math.max(#a, #b) do
        local left = a[i] or 0
        local right = b[i] or 0
        if left ~= right then return left > right end
    end
    return false
end

function Update.check(local_version, callback)
    fetch_first(Update.VERSION_FILE, function(ok, body, err)
        if not ok then
            callback(false, nil, err)
            return
        end
        local remote = body:match('version%s*=%s*"([%d%.]+)"')
        if not remote then
            callback(false, nil, "bad_meta")
            return
        end
        Log.write("update", "remote version: " .. tostring(remote) .. " (local " .. tostring(local_version) .. ")")
        callback(true, remote, nil)
    end, os.time())
end

local function parse_manifest(body)
    local files = {}
    for line in tostring(body):gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:match("^[%w%._%-/]+$") then
            files[#files + 1] = line
        end
    end
    return files
end

local function list_files(callback, cache_bust, version)
    fetch_first(Update.MANIFEST_FILE, function(ok, body)
        if ok then
            local files = parse_manifest(body)
            if #files > 0 then
                callback(files)
                return
            end
        end
        callback(Update.FILES)
    end, cache_bust, version)
end

-- A missing optional file (documentation, manifest) must not abort a release
-- that otherwise installs cleanly.
local OPTIONAL = {
    ["README.md"] = true,
    ["manifest.txt"] = true,
}

local function write_file(path, body)
    local handle = io.open(path, "wb")
    if not handle then return false end
    local ok = handle:write(body)
    handle:close()
    return ok and true or false
end

local function ensure_dir(path)
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        lfs.mkdir(path)
    end)
end

-- Downloads every file to "<name>.new" first. Only when the whole set is
-- present are the temporary files moved over the originals.
function Update.install(plugin_dir, callback, version)
    Log.write("update", "install started: " .. tostring(plugin_dir) .. " v" .. tostring(version))
    local cache_bust = version or os.time()
    list_files(function(files)
        local pending = {}
        local index = 1
        local function next_file()
            if index > #files then
                for _, name in ipairs(pending) do
                    local tmp = plugin_dir .. "/" .. name .. ".new"
                    local final = plugin_dir .. "/" .. name
                    local ok, err = os.rename(tmp, final)
                    if not ok then
                        Log.write("update", "commit failed: " .. name .. " " .. tostring(err))
                        callback(false, name)
                        return
                    end
                end
                Log.write("update", "install committed: " .. #pending .. " files")
                callback(true)
                return
            end
            local name = files[index]
            index = index + 1
            fetch_first(name, function(ok, body)
                if not ok then
                    if OPTIONAL[name] then
                        Log.write("update", "optional file skipped: " .. name)
                        next_file()
                        return
                    end
                    Log.write("update", "download failed: " .. name .. " " .. tostring(body))
                    callback(false, name)
                    return
                end
                if name:find("/") then
                    local dir = plugin_dir .. "/" .. name:match("^(.*)/")
                    ensure_dir(dir)
                end
                local tmp = plugin_dir .. "/" .. name .. ".new"
                if not write_file(tmp, body) then
                    Log.write("update", "write failed: " .. tmp)
                    callback(false, name)
                    return
                end
                pending[#pending + 1] = name
                next_file()
            end, cache_bust, version)
        end
        next_file()
    end, cache_bust, version)
end

return Update
