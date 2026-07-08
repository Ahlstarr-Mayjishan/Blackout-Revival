--[[
    ========================================================================
    Player Modifier - AutoBash Module
    ========================================================================
    Automatically breaks open locked doors and bashes close melee enemies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

local AutoBash = {}
AutoBash.Name = "Auto-Bash Logic"
AutoBash.Description = "Automatically bashes locked doors and close targets using weapons."

local cachedDoors = {}
local lastDoorScanAt = 0
local DOOR_SCAN_INTERVAL = 5

local function refreshDoorCache()
    local now = os.clock()
    if now - lastDoorScanAt < DOOR_SCAN_INTERVAL and #cachedDoors > 0 then
        return cachedDoors
    end

    lastDoorScanAt = now
    table.clear(cachedDoors)

    pcall(function()
        for _, door in ipairs(CollectionService:GetTagged("Doors")) do
            if door:IsA("Model") then
                table.insert(cachedDoors, door)
            end
        end
    end)

    if #cachedDoors == 0 then
        pcall(function()
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("Model") and descendant:HasTag("Doors") then
                    table.insert(cachedDoors, descendant)
                end
            end
        end)
    end

    return cachedDoors
end

-- Helper to find the closest door or enemy in range
local function getClosestBashTarget(range)
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local localPos = localChar.HumanoidRootPart.Position
    local closest = nil
    local closestDist = range
    local targetType = nil
    
    -- 1. Scan for locked doors
    local doors = refreshDoorCache()
    
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
    _G.ModifierRuntime = _G.ModifierRuntime or {}
    if _G.ModifierRuntime.AutoBashThread and coroutine.status(_G.ModifierRuntime.AutoBashThread) ~= "dead" then
        print("[Player Modifier - AutoBash] Worker already running.")
        return
    end

    local bashRemote = ReplicatedStorage:WaitForChild("Events", 5) 
        and ReplicatedStorage.Events:WaitForChild("Player", 5) 
        and ReplicatedStorage.Events.Player:WaitForChild("Bash", 5)

    local isBashing = false
    local loopThread = task.spawn(function()
        while true do
            local delayTime = 0.2
            if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                delayTime = _G.PerformanceGuard.GetDelay(delayTime, "heavy")
            end

            task.wait(delayTime)
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

    _G.ModifierRuntime.AutoBashThread = loopThread

    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, loopThread)
    end
    print("[Player Modifier - AutoBash] Initialized.")
end

return AutoBash
