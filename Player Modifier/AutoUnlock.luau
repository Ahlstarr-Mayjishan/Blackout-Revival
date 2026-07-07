--[[
    ========================================================================
    Player Modifier - AutoUnlock Module (Instant Win Loot Minigames Logic)
    ========================================================================
    This module contains the background execution logic for Auto-Unlock Safes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoUnlock = {}
AutoUnlock.Name = "Auto-Unlock Safes Logic"
AutoUnlock.Description = "Handles automated safe-cracking and door-opening minigame completion."

function AutoUnlock:Init(UIRef)
    local lootFolder = ReplicatedStorage:WaitForChild("Events", 5) and ReplicatedStorage.Events:WaitForChild("Loot", 5)
    if not lootFolder then
        return
    end
    
    local minigameEvent = lootFolder:WaitForChild("Minigame", 5)
    local resultEvent = lootFolder:WaitForChild("MinigameResult", 5)
    
    if minigameEvent and resultEvent then
        -- Intercept start event and fire completion event
        local connection = minigameEvent.OnClientEvent:Connect(function(minigameId, ...)
            if _G.ModifierStates and _G.ModifierStates.AutoUnlock then
                print("[Player Modifier - AutoUnlock] Auto-completing minigame: " .. tostring(minigameId))
                task.spawn(function()
                    task.wait(0.1) -- Emulate real delay
                    resultEvent:FireServer(minigameId, true)
                end)
            end
        end)
        
        -- Register connection for GC cleanup
        if _G.ModifierConnections then
            table.insert(_G.ModifierConnections, connection)
        end
        
        print("[Player Modifier - AutoUnlock] Safe minigame event handler connected.")
    end
end

return AutoUnlock
