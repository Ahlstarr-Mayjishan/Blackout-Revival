--[[
    ========================================================================
    Blackout/Nightbound - Standalone Self-Revive Test Script
    ========================================================================
    This script is designed to test the Self-Revive feature independently.
    
    Features:
    1. Instant Self-Revive on execution.
    2. Auto Self-Revive Loop (detects if you are downed and attempts to revive).
    3. Manual Keybind Trigger (Press "P" to attempt a self-revive manually).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Reference to the Revive RemoteEvent
local reviveRemote = ReplicatedStorage:WaitForChild("Events", 5) 
    and ReplicatedStorage.Events:WaitForChild("Actions", 5) 
    and ReplicatedStorage.Events.Actions:WaitForChild("Revive", 5)

if not reviveRemote then
    error("[Self-Revive Test] Revive RemoteEvent not found under ReplicatedStorage.Events.Actions.Revive")
end

local function attemptSelfRevive()
    local character = LocalPlayer.Character
    if not character then
        print("[Self-Revive Test] Character not found, cannot revive.")
        return
    end
    
    print("[Self-Revive Test] Attempting to revive yourself: Firing ReplicatedStorage.Events.Actions.Revive")
    
    -- Fire the remote event targeting yourself
    local success, err = pcall(function()
        reviveRemote:FireServer(character)
    end)
    
    if success then
        print("[Self-Revive Test] Successfully fired Revive remote targeting: " .. tostring(character.Name))
    else
        warn("[Self-Revive Test] Failed to fire Revive remote: " .. tostring(err))
    end
end

-- 1. Execute once immediately on script injection
attemptSelfRevive()

-- 2. Bind a key (Press "P" to manually trigger self-revive)
local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.P then
        print("[Self-Revive Test] 'P' pressed. Manually triggering self-revive...")
        attemptSelfRevive()
    end
end)

-- 3. Auto-Revive Loop (Scans for Downed attribute or state)
_G.TestSelfReviveActive = true
task.spawn(function()
    print("[Self-Revive Test] Auto-detect loop started. Press 'P' to manually revive.")
    while _G.TestSelfReviveActive do
        task.wait(0.5)
        local character = LocalPlayer.Character
        if character then
            -- Check if character has the Downed attribute or Health is <= 25 (common downed indicator)
            local isDowned = character:GetAttribute("Downed") == true 
                or character:GetAttribute("Ragdolled") == true
                or (character:FindFirstChild("Humanoid") and character.Humanoid.Health <= 25 and character.Humanoid.Health > 0)
                
            if isDowned then
                print("[Self-Revive Test] Downed state detected! Auto-reviving...")
                attemptSelfRevive()
                task.wait(2) -- Cooldown before trying again
            end
        end
    end
end)

-- Unload mechanism in case you want to stop the test script
_G.StopSelfReviveTest = function()
    _G.TestSelfReviveActive = false
    if connection then
        connection:Disconnect()
    end
    print("[Self-Revive Test] Test script successfully unloaded.")
end
