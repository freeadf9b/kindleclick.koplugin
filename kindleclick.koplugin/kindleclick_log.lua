--[[--
Small append-only log for Bluetooth state transitions and wake recovery.

Deep-sleep failures can only be diagnosed from what happened *before* the
failure, so every power request, resume and recovery step is recorded here.
The file is capped; one previous generation is kept as kindleclick.log.1.
--]]

local Device = require("device")

local Log = {}

local LOG_PATH = (Device.home_dir or "/mnt/us") .. "/koreader/kindleclick.log"
local MAX_BYTES = 64 * 1024

function Log.path()
    return LOG_PATH
end

local function rotate()
    os.remove(LOG_PATH .. ".1")
    os.rename(LOG_PATH, LOG_PATH .. ".1")
end

function Log.write(tag, message)
    pcall(function()
        local file = io.open(LOG_PATH, "a")
        if not file then return end
        local size = file:seek("end") or 0
        if size > MAX_BYTES then
            file:close()
            rotate()
            file = io.open(LOG_PATH, "a")
            if not file then return end
        end
        file:write(string.format("%s [%s] %s\n",
            os.date("%Y-%m-%d %H:%M:%S"), tostring(tag), tostring(message)))
        file:close()
    end)
end

-- Last `count` lines, for the diagnostic report.
function Log.tail(count)
    local lines = {}
    pcall(function()
        local file = io.open(LOG_PATH, "r")
        if not file then return end
        local size = file:seek("end") or 0
        local window = math.min(size, 8192)
        file:seek("set", size - window)
        local text = file:read("*a") or ""
        file:close()
        for line in text:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        while #lines > (count or 40) do
            table.remove(lines, 1)
        end
    end)
    return table.concat(lines, "\n")
end

return Log
