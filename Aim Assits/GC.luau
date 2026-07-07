--[[
    ========================================================================
    Aim Assits - GC Module (Garbage Collection and Cleanup Routine)
    ========================================================================
    This module cleans up the Aim Assist framework by disconnecting events,
    removing drawing objects (like FOV circle), and clearing global state variables.
]]

local GC = {}
GC.Name = "Garbage Collection"
GC.Description = "Internal framework module that unbinds aim events and disposes of drawing circles."

local function log(msg)
    print("[Aim Assist - GC] " .. tostring(msg))
end

-- Dispose of connections and vector circles
local function cleanupConnections()
    local connCount = 0
    local drawCount = 0
    
    if _G.AimAssistConnections then
        for _, item in ipairs(_G.AimAssistConnections) do
            if typeof(item) == "RBXScriptConnection" then
                if item.Connected then
                    item:Disconnect()
                    connCount = connCount + 1
                end
            elseif type(item) == "table" and type(item.Remove) == "function" then
                -- Drawing API objects (like Circle) are removed via Remove method
                local success, err = pcall(function()
                    item:Remove()
                end)
                if success then
                    drawCount = drawCount + 1
                else
                    warn("Failed to remove drawing item: " .. tostring(err))
                end
            end
        end
        table.clear(_G.AimAssistConnections)
    end
    
    log("Disconnected " .. tostring(connCount) .. " event connections and cleared " .. tostring(drawCount) .. " drawing objects.")
end
-- Restore any hooked functions
local function restoreHooks()
    if not _G.AimAssistOriginals then
        return
    end
    
    -- 1. Restore FastCast.Fire hook
    if _G.AimAssistOriginals["FastCast_Fire"] then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local modsFolder = ReplicatedStorage:WaitForChild("Mods", 5)
        local fastCastModule = modsFolder and modsFolder:WaitForChild("FastCast", 5)
        if fastCastModule then
            local success, fastCastTable = pcall(require, fastCastModule)
            if success and type(fastCastTable) == "table" then
                fastCastTable.Fire = _G.AimAssistOriginals["FastCast_Fire"]
                log("Restored original FastCast.Fire method successfully.")
            end
        end
        _G.AimAssistOriginals["FastCast_Fire"] = nil
    end

    -- 2. Restore __namecall raycast hook
    if _G.AimAssistOriginals["Raycast_Metatable"] then
        if hookmetamethod then
            local success, err = pcall(function()
                hookmetamethod(game, "__namecall", _G.AimAssistOriginals["Raycast_Metatable"])
            end)
            if success then
                log("Restored original __namecall raycast method successfully.")
            else
                warn("Failed to restore __namecall raycast: " .. tostring(err))
            end
        end
        _G.AimAssistOriginals["Raycast_Metatable"] = nil
    end
    
    -- 3. Restore Workspace.Raycast direct function hook
    if _G.AimAssistOriginals["Raycast_Function"] then
        if hookfunction then
            local success, err = pcall(function()
                local Workspace = game:GetService("Workspace")
                hookfunction(Workspace.Raycast, _G.AimAssistOriginals["Raycast_Function"])
            end)
            if success then
                log("Restored original Workspace.Raycast function successfully.")
            else
                warn("Failed to restore Workspace.Raycast function: " .. tostring(err))
            end
        end
        _G.AimAssistOriginals["Raycast_Function"] = nil
    end

    table.clear(_G.AimAssistOriginals)
end

-- Full cleanup execution
function GC.cleanup()
    log("Starting clean up routine...")
    
    -- Turn off states first to halt threads
    if _G.AimAssistStates then
        for k, _ in pairs(_G.AimAssistStates) do
            _G.AimAssistStates[k] = false
        end
    end
    
    cleanupConnections()
    restoreHooks()
    
    -- Clear globals
    _G.AimAssistStates = nil
    _G.AimAssistConnections = nil
    _G.AimAssistOriginals = nil
    
    log("Clean up finished successfully.")
end

function GC:Init(UIRef)
    log("GC module loaded. Expose GC.cleanup() for script termination.")
end

return GC
