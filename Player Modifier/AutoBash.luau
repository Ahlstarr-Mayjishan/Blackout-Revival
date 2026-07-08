--[[
    ========================================================================
    Player Modifier - AutoBash Module
    ========================================================================
    Automatically breaks open locked doors and bashes close melee enemies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local AutoBash = {}
AutoBash.Name = "Auto-Bash Logic"
AutoBash.Description = "Automatically bashes locked doors and close targets using weapons."

-- Helper to find the closest door or enemy in range
local function getClosestBashTarget(range)
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local localPos = localChar.HumanoidRootPart.Position
    local closest = nil
    local closestDist = range
    local targetType = nil
    
    -- 1. Scan for locked doors
    local doors = {}
    pcall(function()
        doors = game:GetService("CollectionService"):GetTagged("Doors")
    end)
    if #doors == 0 then
        for _, descendant in ipairs(workspace:GetDescendants()) do
            if descendant:IsA("Model") and descendant:HasTag("Doors") then
                table.insert(doors, descendant)
            end
        end
    end
    
    for _, door in ipairs(doors) do
        if door:GetAttribute("Locked") == true and not door:GetAttribute("Broken") then
            local primary = door.PrimaryPart or door:FindFirstChildWhichIsA("BasePart")
            if primary then
                local dist = (primary.Position - localPos).Magnitude
                if dist < closestDist then
                    closest = door
                    closestDist = dist
                    targetType = "Door"
                end
            end
        end
    end
    
    -- 2. Scan for close enemies (if enabled in UI options)
    if _G.ModifierStates and _G.ModifierStates.AutoBashEnemies then
        local targets = {}
        local chars = workspace:FindFirstChild("Chars")
        if chars then
            for _, char in ipairs(chars:GetChildren()) do
                if char:IsA("Model") and char ~= localChar then
                    local player = Players:GetPlayerFromCharacter(char)
                    local isEnemy = true
                    if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
                        isEnemy = false
                    end
                    if isEnemy and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
                        table.insert(targets, char)
                    end
                end
            end
        end
        
        for _, char in ipairs(targets) do
            local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
            if root then
                local dist = (root.Position - localPos).Magnitude
                if dist < closestDist then
                    closest = char
                    closestDist = dist
                    targetType = "Enemy"
                end
            end
        end
    end
    
    return closest, targetType
end

function AutoBash:Init(UIRef)
    local bashRemote = ReplicatedStorage:WaitForChild("Events", 5) 
        and ReplicatedStorage.Events:WaitForChild("Player", 5) 
        and ReplicatedStorage.Events.Player:WaitForChild("Bash", 5)

    local isBashing = false
    local loopThread = task.spawn(function()
        while true do
            task.wait(0.2)
            if not _G.ModifierStates then break end

            if _G.ModifierStates.AutoBash and bashRemote and not isBashing then
                local target, targetType = getClosestBashTarget(8)
                if target then
                    isBashing = true
                    pcall(function()
                        local direction = true
                        local primary = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
                        local localChar = LocalPlayer.Character
                        if primary and localChar and localChar:FindFirstChild("HumanoidRootPart") then
                            -- Determine bash direction/side based on relative position dot product
                            direction = primary.CFrame.RightVector:Dot((localChar.HumanoidRootPart.Position - primary.Position).Unit) > 0
                        end
                        
                        bashRemote:FireServer(target, direction)
                    end)
                    task.wait(1.0) -- Cooldown buffer to prevent spam kick
                    isBashing = false
                end
            end
        end
    end)

    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, loopThread)
    end
    print("[Player Modifier - AutoBash] Initialized.")
end

return AutoBash
