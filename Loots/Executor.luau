--[[
    ========================================================================
    Loots - Executor
    ========================================================================
    Lightweight bootstrap/runtime marker for the Loots suite.
]]

local Executor = {}
Executor.Name = "Loots Executor"
Executor.Description = "Initializes shared Loots runtime state."

local function log(message)
    print("[Loots - Executor] " .. tostring(message))
end

function Executor:Init(UIRef)
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}
    _G.LootRuntime.ExecutorLoaded = true
    log("Runtime ready.")
end

return Executor
