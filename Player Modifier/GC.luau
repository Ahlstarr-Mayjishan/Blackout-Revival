--[[
    ========================================================================
    Player Modifier - GC Module (Garbage Collection & Cleanup Framework)
    ========================================================================
    This module cleans up the framework by restoring all modified/hooked methods
    and disconnecting all active RBXScriptConnections to prevent memory leaks
    and execution errors when the script unloads or restarts.
]]

local GC = {}
GC.Name = "Garbage Collection"
GC.Description = "Internal framework module that unhooks functions and cleans up connections."

local function log(msg)
    print("[Player Modifier - GC] " .. tostring(msg))
end

-- Disconnect all event listeners
local function cleanupConnections()
    local count = 0
    local threadCount = 0
    local objectCount = 0
    if _G.ModifierConnections then
        for _, connection in ipairs(_G.ModifierConnections) do
            if typeof(connection) == "RBXScriptConnection" and connection.Connected then
                connection:Disconnect()
                count = count + 1
            elseif typeof(connection) == "thread" then
                pcall(function()
                    task.cancel(connection)
                end)
                threadCount = threadCount + 1
            elseif type(connection) == "table" and type(connection.Destroy) == "function" then
                pcall(function()
                    connection:Destroy()
                end)
                objectCount = objectCount + 1
            elseif type(connection) == "table" and type(connection.Remove) == "function" then
                pcall(function()
                    connection:Remove()
                end)
                objectCount = objectCount + 1
            end
        end
        table.clear(_G.ModifierConnections)
    end
    log("Disconnected " .. tostring(count) .. " active event connections, cancelled " .. tostring(threadCount) .. " threads, and destroyed " .. tostring(objectCount) .. " cleanup handles.")
end

-- Restore hooked metatable and functions
local function restoreHooks()
    -- Restore Melee Raycast __namecall hook before Player remote __namecall hook.
    -- Hooks stack, so cleanup must unwind them in reverse install order.
    if _G.OriginalFunctions and _G.OriginalFunctions["MeleeRaycast_Metatable"] then
        if hookmetamethod then
            local success, err = pcall(function()
                hookmetamethod(game, "__namecall", _G.OriginalFunctions["MeleeRaycast_Metatable"])
            end)
            if success then
                log("Restored original __namecall raycast method successfully.")
            else
                warn("Failed to restore __namecall raycast method: " .. tostring(err))
            end
        end
        _G.OriginalFunctions["MeleeRaycast_Metatable"] = nil
    end

    -- 1. Restore __namecall hook
    if _G.OriginalFunctions and (_G.OriginalFunctions["namecall"] or _G.OriginalFunctions["PlayerRemote_Namecall"]) then
        if hookmetamethod then
            local success, err = pcall(function()
                hookmetamethod(game, "__namecall", _G.OriginalFunctions["PlayerRemote_Namecall"] or _G.OriginalFunctions["namecall"])
            end)
            if success then
                log("Restored original __namecall method successfully.")
            else
                warn("Failed to restore __namecall metatable: " .. tostring(err))
            end
        end
        _G.OriginalFunctions["namecall"] = nil
        _G.OriginalFunctions["PlayerRemote_Namecall"] = nil
    end
    
    -- 2. Restore FireServer function hook
    if _G.OriginalFunctions and (_G.OriginalFunctions["FireServer"] or _G.OriginalFunctions["PlayerRemote_FireServer"]) then
        if hookfunction then
            local success, err = pcall(function()
                if _G.OriginalFunctions["PlayerRemote_FireServer"] then
                    local ReplicatedStorage = game:GetService("ReplicatedStorage")
                    local playerEvents = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Player")
                    local originals = _G.OriginalFunctions["PlayerRemote_FireServer"]

                    if playerEvents and originals.Damage and playerEvents:FindFirstChild("Damage") then
                        hookfunction(playerEvents.Damage.FireServer, originals.Damage)
                    end

                    if playerEvents and originals.Ragdoll and playerEvents:FindFirstChild("Ragdoll") then
                        hookfunction(playerEvents.Ragdoll.FireServer, originals.Ragdoll)
                    end
                else
                    local dummyRemote = Instance.new("RemoteEvent")
                    hookfunction(dummyRemote.FireServer, _G.OriginalFunctions["FireServer"])
                    dummyRemote:Destroy()
                end
            end)
            if success then
                log("Restored original FireServer method successfully.")
            else
                warn("Failed to restore FireServer method: " .. tostring(err))
            end
        end
        _G.OriginalFunctions["FireServer"] = nil
        _G.OriginalFunctions["PlayerRemote_FireServer"] = nil
    end
    
    -- 3. Restore GetAttribute hook
    if _G.OriginalFunctions and _G.OriginalFunctions["GetAttribute"] then
        if hookfunction then
            local success, err = pcall(function()
                local dummyInstance = Instance.new("Folder")
                hookfunction(dummyInstance.GetAttribute, _G.OriginalFunctions["GetAttribute"])
                dummyInstance:Destroy()
            end)
            if success then
                log("Restored original GetAttribute method successfully.")
            else
                warn("Failed to restore GetAttribute method: " .. tostring(err))
            end
        end
        _G.OriginalFunctions["GetAttribute"] = nil
    end

    -- Restore InfiniteStamina namecall hook
    if _G.OriginalFunctions and _G.OriginalFunctions["InfiniteStamina_Namecall"] then
        if hookmetamethod then
            pcall(function()
                hookmetamethod(game, "__namecall", _G.OriginalFunctions["InfiniteStamina_Namecall"])
                log("Restored InfiniteStamina namecall hook successfully.")
            end)
        end
        _G.OriginalFunctions["InfiniteStamina_Namecall"] = nil
    end

    -- Restore Stamina FireServer hook
    if _G.OriginalFunctions and _G.OriginalFunctions["Stamina_FireServer"] then
        if hookfunction then
            pcall(function()
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local staminaRemote = ReplicatedStorage:FindFirstChild("Events")
                    and ReplicatedStorage.Events:FindFirstChild("Player")
                    and ReplicatedStorage.Events.Player:FindFirstChild("Stamina")
                if staminaRemote then
                    hookfunction(staminaRemote.FireServer, _G.OriginalFunctions["Stamina_FireServer"])
                    log("Restored original Stamina.FireServer successfully.")
                end
            end)
        end
        _G.OriginalFunctions["Stamina_FireServer"] = nil
    end

    -- Restore WalkSpeed NewIndex hook
    if _G.OriginalFunctions and _G.OriginalFunctions["WalkSpeed_NewIndex"] then
        if hookmetamethod then
            pcall(function()
                hookmetamethod(game, "__newindex", _G.OriginalFunctions["WalkSpeed_NewIndex"])
                log("Restored original __newindex WalkSpeed handler successfully.")
            end)
        end
        _G.OriginalFunctions["WalkSpeed_NewIndex"] = nil
    end

    -- Restore Flashbang Connect hook
    if _G.OriginalFunctions and _G.OriginalFunctions["AntiFlashbang_Namecall"] then
        if hookmetamethod then
            pcall(function()
                hookmetamethod(game, "__namecall", _G.OriginalFunctions["AntiFlashbang_Namecall"])
                log("Restored AntiFlashbang namecall hook successfully.")
            end)
        end
        _G.OriginalFunctions["AntiFlashbang_Namecall"] = nil
    end

    if _G.OriginalFunctions and _G.OriginalFunctions["Flashbang_Connect"] then
        if hookfunction then
            pcall(function()
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local flashbangRemote = ReplicatedStorage:FindFirstChild("Events")
                    and ReplicatedStorage.Events:FindFirstChild("Player")
                    and ReplicatedStorage.Events.Player:FindFirstChild("Flashbang")
                if flashbangRemote then
                    hookfunction(flashbangRemote.OnClientEvent.Connect, _G.OriginalFunctions["Flashbang_Connect"])
                    log("Restored original Flashbang.OnClientEvent.Connect successfully.")
                end
            end)
        end
        _G.OriginalFunctions["Flashbang_Connect"] = nil
    end

    if _G.OriginalFunctions and _G.OriginalFunctions["MeleeRaycast_Function"] then
        if hookfunction then
            local success, err = pcall(function()
                local Workspace = game:GetService("Workspace")
                hookfunction(Workspace.Raycast, _G.OriginalFunctions["MeleeRaycast_Function"])
            end)
            if success then
                log("Restored original Workspace.Raycast method successfully.")
            end
        end
        _G.OriginalFunctions["MeleeRaycast_Function"] = nil
    end
    
    -- 4. Restore _G Proxy Metatable if exists
    local mt = getmetatable(_G)
    if mt and mt.__isProxy then
        setmetatable(_G, nil)
        log("Restored original _G metatable.")
    end
end

-- Full cleanup routine
function GC.cleanup()
    log("Starting clean up...")

    if _G.PerformanceGuard and type(_G.PerformanceGuard.Cleanup) == "function" then
        pcall(function()
            _G.PerformanceGuard.Cleanup()
        end)
    end
    
    -- Set all states to false to stop loop executions
    if _G.ModifierStates then
        for k, _ in pairs(_G.ModifierStates) do
            _G.ModifierStates[k] = false
        end
    end
    
    cleanupConnections()
    restoreHooks()
    
    -- Optional: Clear tables entirely if shutting down
    _G.ModifierStates = nil
    _G.ModifierConnections = nil
    _G.ModifierRuntime = nil
    _G.OriginalFunctions = nil
    _G.PerformanceGuard = nil
    _G.PerformanceGuardState = nil
    
    log("Cleanup completed successfully.")
end

function GC:Init(UIRef)
    -- This module registers the cleanup utility; it does not inject UI elements directly.
    log("GC module loaded. Expose GC.cleanup() for script termination.")
end

return GC
