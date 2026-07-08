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
    local threadCount = 0
    local objectCount = 0
    
    if _G.AimAssistConnections then
        for _, item in ipairs(_G.AimAssistConnections) do
            if typeof(item) == "RBXScriptConnection" then
                if item.Connected then
                    item:Disconnect()
                    connCount = connCount + 1
                end
            elseif typeof(item) == "thread" then
                pcall(function()
                    task.cancel(item)
                end)
                threadCount = threadCount + 1
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
            elseif type(item) == "table" and type(item.Destroy) == "function" then
                pcall(function()
                    item:Destroy()
                end)
                objectCount = objectCount + 1
            end
        end
        table.clear(_G.AimAssistConnections)
    end
    
    log("Disconnected " .. tostring(connCount) .. " event connections, cancelled " .. tostring(threadCount) .. " threads, cleared " .. tostring(drawCount) .. " drawing objects, and destroyed " .. tostring(objectCount) .. " cleanup handles.")
end

-- Restore any hooked functions
local function restoreHooks()
    if not _G.AimAssistOriginals then
        return
    end

    if _G.AimAssistOriginals.RecoilControlStats then
        local success, err = pcall(function()
            for container, values in pairs(_G.AimAssistOriginals.RecoilControlStats) do
                if type(container) == "table" then
                    for key, value in pairs(values) do
                        container[key] = value
                    end
                elseif typeof(container) == "Instance" and container.Parent then
                    for key, value in pairs(values) do
                        container:SetAttribute(key, value)
                    end
                end
            end
        end)

        if success then
            log("Restored RecoilControl weapon stats successfully.")
        else
            warn("Failed to restore RecoilControl weapon stats: " .. tostring(err))
        end

        _G.AimAssistOriginals.RecoilControlStats = nil
    end

    if _G.AimAssistOriginals["HomingBullets_FastCast_Fire"] then
        local success, err = pcall(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local fastCastModule = ReplicatedStorage:FindFirstChild("Mods") and ReplicatedStorage.Mods:FindFirstChild("FastCast")
            if fastCastModule then
                local fastCastTable = require(fastCastModule)
                fastCastTable.Fire = _G.AimAssistOriginals["HomingBullets_FastCast_Fire"]
            end
        end)

        if success then
            log("Restored HomingBullets FastCast.Fire successfully.")
        else
            warn("Failed to restore HomingBullets FastCast.Fire: " .. tostring(err))
        end

        _G.AimAssistOriginals["HomingBullets_FastCast_Fire"] = nil
    end

    if _G.AimAssistOriginals["HomingBullets_BulletHandler_Fire"] then
        local success, err = pcall(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local gunStorage = ReplicatedStorage:FindFirstChild("GunStorage")
            local bulletHandlerModule = gunStorage
                and gunStorage:FindFirstChild("Mods")
                and gunStorage.Mods:FindFirstChild("BulletHandler")

            if bulletHandlerModule then
                local bulletHandler = require(bulletHandlerModule)
                bulletHandler.Fire = _G.AimAssistOriginals["HomingBullets_BulletHandler_Fire"]
            end
        end)

        if success then
            log("Restored HomingBullets BulletHandler.Fire successfully.")
        else
            warn("Failed to restore HomingBullets BulletHandler.Fire: " .. tostring(err))
        end

        _G.AimAssistOriginals["HomingBullets_BulletHandler_Fire"] = nil
    end
    
    -- 1. Restore __namecall raycast hook
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
    
    -- 2. Restore Workspace.Raycast direct function hook
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

    if _G.AimAssistOriginals["FastCast_Fire"] then
        local success, err = pcall(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local fastCastModule = ReplicatedStorage:FindFirstChild("Mods") and ReplicatedStorage.Mods:FindFirstChild("FastCast")
            if fastCastModule then
                local fastCastTable = require(fastCastModule)
                fastCastTable.Fire = _G.AimAssistOriginals["FastCast_Fire"]
            end
        end)

        if success then
            log("Restored original FastCast.Fire successfully.")
        else
            warn("Failed to restore FastCast.Fire: " .. tostring(err))
        end

        _G.AimAssistOriginals["FastCast_Fire"] = nil
    end

    if _G.AimAssistOriginals["BulletHandler_Fire"] then
        local success, err = pcall(function()
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local gunStorage = ReplicatedStorage:FindFirstChild("GunStorage")
            local bulletHandlerModule = gunStorage
                and gunStorage:FindFirstChild("Mods")
                and gunStorage.Mods:FindFirstChild("BulletHandler")

            if bulletHandlerModule then
                local bulletHandler = require(bulletHandlerModule)
                bulletHandler.Fire = _G.AimAssistOriginals["BulletHandler_Fire"]
            end
        end)

        if success then
            log("Restored original BulletHandler.Fire successfully.")
        else
            warn("Failed to restore BulletHandler.Fire: " .. tostring(err))
        end

        _G.AimAssistOriginals["BulletHandler_Fire"] = nil
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
    _G.AimAssistRuntime = nil
    
    log("Clean up finished successfully.")
end

function GC:Init(UIRef)
    log("GC module loaded. Expose GC.cleanup() for script termination.")
end

return GC
