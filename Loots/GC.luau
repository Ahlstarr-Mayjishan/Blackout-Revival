--[[
    ========================================================================
    Loots - GC Module
    ========================================================================
    Cleans up loot automation runtime state and connections.
]]

local GC = {}
GC.Name = "Loots Garbage Collection"
GC.Description = "Disconnects Loots runtime connections and clears global state."

local function log(message)
    print("[Loots - GC] " .. tostring(message))
end

local function cleanupConnections()
    local count = 0
    local threadCount = 0

    if _G.LootConnections then
        for _, item in ipairs(_G.LootConnections) do
            pcall(function()
                if typeof(item) == "RBXScriptConnection" then
                    if item.Connected then
                        item:Disconnect()
                        count += 1
                    end
                elseif typeof(item) == "thread" then
                    task.cancel(item)
                    threadCount += 1
                elseif type(item) == "table" and type(item.Destroy) == "function" then
                    item:Destroy()
                elseif type(item) == "table" and type(item.Remove) == "function" then
                    item:Remove()
                end
            end)
        end

        table.clear(_G.LootConnections)
    end

    log("Disconnected " .. tostring(count) .. " connections and cancelled " .. tostring(threadCount) .. " threads.")
end

function GC.cleanup()
    if _G.LootStates then
        for key in pairs(_G.LootStates) do
            if type(_G.LootStates[key]) == "boolean" then
                _G.LootStates[key] = false
            end
        end
    end

    cleanupConnections()

    _G.LootStates = nil
    _G.LootConnections = nil
    _G.LootRuntime = nil

    log("Cleanup completed.")
end

function GC:Init(UIRef)
    log("GC module loaded.")
end

return GC
