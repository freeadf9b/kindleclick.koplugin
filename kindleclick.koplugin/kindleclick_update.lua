-- Self-update support for the Kindle Click plugin.
--
-- The plugin lives in a public GitHub repository, so the cheapest reliable
-- updater is a plain file fetch: read the remote _meta.lua to learn the
-- version, then download the file list from the repository root. Nothing is
-- replaced until every file has arrived, so an interrupted download leaves
-- the installed version untouched.

local UIManager = require("ui/uimanager")
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
    "manifest.txt",
    "README.md",
    "fonts/kindleclick-icons.ttf",
}

local function plugin_base(url)
    return url .. "/kindleclick.koplugin/"
end

local function mirrors()
    return {
        plugin_base("https://cdn.jsdelivr.net/gh/" .. Update.REPO .. "@" .. Update.BRANCH),
        plugin_base("https://raw.githubusercontent.com/" .. Update.REPO .. "/" .. Update.BRANCH),
    }
end

-- A single GET with a hard local timeout: the HTTP client is asynchronous, so
-- a dead connection would otherwise leave the UI waiting forever.
local function fetch(url, callback)
    local ok, HTTPClient = pcall(require, "httpclient")
    if not ok then
        callback(false, nil, "no_httpclient")
        return
    end
    local done = false
    local timer
    local function finish(ok_done, body, err)
        if done then return end
        done = true
        if timer then UIManager:unschedule(timer) end
        callback(ok_done, body, err)
    end
    timer = function() finish(false, nil, "timeout") end
    UIManager:scheduleIn(30, timer)
    local sent = pcall(function()
        HTTPClient:new():request({
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = "kindleclick-koplugin" },
        }, function(res)
            if type(res) == "table" and res.code == 200 and type(res.body) == "string" then
                finish(true, res.body)
            else
                finish(false, nil, type(res) == "table" and tostring(res.code) or "no_response")
            end
        end)
    end)
    if not sent then finish(false, nil, "request_failed") end
end

-- jsDelivr caches files for up to 12 hours, which would hide a fresh push.
-- Appending a cache key makes every fetch a distinct URL, so the CDN asks
-- GitHub instead of serving its cached copy.
local function fetch_first(path, callback, cache_bust)
    local urls = mirrors()
    local index = 1
    local function next_mirror()
        if index > #urls then
            callback(false, nil, "unreachable")
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
    fetch_first(Update.VERSION_FILE, function(ok, body)
        if not ok then
            callback(false, nil, body)
            return
        end
        local remote = body:match('version%s*=%s*"([%d%.]+)"')
        if not remote then
            callback(false, nil, "bad_meta")
            return
        end
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

local function list_files(callback, cache_bust)
    fetch_first(Update.MANIFEST_FILE, function(ok, body)
        if ok then
            local files = parse_manifest(body)
            if #files > 0 then
                callback(files)
                return
            end
        end
        callback(Update.FILES)
    end, cache_bust)
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
            end, cache_bust)
        end
        next_file()
    end, cache_bust)
end

return Update
