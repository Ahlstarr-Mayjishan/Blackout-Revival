--[[
    ========================================================================
    Player Modifier - AuraActions Module
    ========================================================================
    Handles automated aura-based actions including Revive Aura and Finisher Aura.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local AuraActions = {}
AuraActions.Name = "Aura Actions Logic"
AuraActions.Description = "Automates reviving teammates and executing downed enemies in range."

-- Helper to find the closest downed teammate within a specified radius
local function getClosestDownedTeammate(range)
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then return nil end
    local localPos = localChar.HumanoidRootPart.Position
    local closest = nil
    local closestDist = range
    
    local chars = workspace:FindFirstChild("Chars")
    if chars then
        for _, char in ipairs(chars:GetChildren()) do
            if char:IsA("Model") and char ~= localChar then
                local player = Players:GetPlayerFromCharacter(char)
                local isTeammate = false
                
                -- Check if teammate is on the same team (ignoring neutral/nil)
                if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
                    isTeammate = true
                end
                
                -- Detect Downed attribute or low health threshold
                local isDowned = char:GetAttribute("Downed") == true 
                    or (char:FindFirstChild("Humanoid") and char.Humanoid.Health <= 25 and char.Humanoid.Health > 0)
                
                if isTeammate and isDowned then
                    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                    if root then
                        local dist = (root.Position - localPos).Magnitude
                        if dist < closestDist then
                            closest = char
                            closestDist = dist
                        end
                    end
                end
            end
        end
    end
    return closest
end

-- Helper to find the closest downed enemy/NPC within a specified radius
local function getClosestDownedEnemy(range)
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then return nil end
    local localPos = localChar.HumanoidRootPart.Position
    local closest = nil
    local closestDist = range
    
    local targets = {}
    
    -- Gather potential player targets
    local chars = workspace:FindFirstChild("Chars")
    if chars then
        for _, char in ipairs(chars:GetChildren()) do
            if char:IsA("Model") and char ~= localChar then
                local player = Players:GetPlayerFromCharacter(char)
                local isEnemy = true
                if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
                    isEnemy = false
                end
                if isEnemy then
                    table.insert(targets, char)
                end
            end
        end
    end
    
    -- Gather potential NPC targets (checks standard NPCs folders)
    local npcs = workspace:FindFirstChild("NPCs")
    if npcs then
        for _, folder in ipairs(npcs:GetChildren()) do
            if folder:IsA("Folder") or folder:IsA("Model") then
                for _, npc in ipairs(folder:GetChildren()) do
                    if npc:IsA("Model") then
                        table.insert(targets, npc)
                    end
                end
                if folder:IsA("Model") then
                    table.insert(targets, folder)
                end
            end
        end
    end
    
    -- Scan through all compiled targets
    for _, char in ipairs(targets) do
        local isDowned = char:GetAttribute("Downed") == true 
            or (char:FindFirstChild("Humanoid") and char.Humanoid.Health <= 25 and char.Humanoid.Health > 0)
            
        if isDowned then
            local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
            if root then
                local dist = (root.Position - localPos).Magnitude
                if dist < closestDist then
                    closest = char
                    closestDist = dist
                end
            end
        end
    end
    return closest
end

function AuraActions:Init(UIRef)
    _G.ModifierRuntime = _G.ModifierRuntime or {}
    if _G.ModifierRuntime.AuraActionsThread and coroutine.status(_G.ModifierRuntime.AuraActionsThread) ~= "dead" then
        print("[Player Modifier - AuraActions] Worker already running.")
        return
    end

    local reviveRemote = ReplicatedStorage:WaitForChild("Events", 5) 
        and ReplicatedStorage.Events:WaitForChild("Actions", 5) 
        and ReplicatedStorage.Events.Actions:WaitForChild("Revive", 5)
        
    local finishRemote = ReplicatedStorage:WaitForChild("Events", 5) 
        and ReplicatedStorage.Events:WaitForChild("Actions", 5) 
        and ReplicatedStorage.Events.Actions:WaitForChild("Finish", 5)

    -- Background Thread for Aura Scanning
    local loopThread = task.spawn(function()
        while true do
            local delayTime = 0.3
            if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                delayTime = _G.PerformanceGuard.GetDelay(delayTime, "heavy")
            end

            task.wait(delayTime)
            
            -- Exit loop if ModifierStates has been destroyed/cleaned
            if not _G.ModifierStates then break end

            -- 1. Revive Aura
            if _G.ModifierStates.ReviveAura and reviveRemote then
                local teammate = getClosestDownedTeammate(_G.ModifierStates.ReviveAuraRange or 20)
                if teammate then
                    pcall(function()
                        reviveRemote:FireServer(teammate)
                    end)
                end
            end
            
            -- 2. Finisher Aura
            if _G.ModifierStates.FinisherAura and finishRemote then
                local enemy = getClosestDownedEnemy(_G.ModifierStates.FinisherAuraRange or 15)
                if enemy then
                    pcall(function()
                        finishRemote:FireServer(enemy)
                    end)
                end
            end
        end
    end)

    _G.ModifierRuntime.AuraActionsThread = loopThread

    -- Register thread for GC cleanup (handled by stopping conditions or thread cancel)
    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, loopThread)
    end
    print("[Player Modifier - AuraActions] Initialized.")
end

return AuraActions
