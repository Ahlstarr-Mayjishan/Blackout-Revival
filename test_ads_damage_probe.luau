--[[
    ========================================================================
    Blackout/Nightbound - ADS vs Hip-fire Damage Probe
    ========================================================================

    Purpose:
    - Test whether ADS/aiming improves real server damage validation.
    - Logs every shot attempt with inferred ADS state, spread stats, target
      distance, and whether an NPC health drop follows shortly after.

    Stop:
        _G.StopADSDamageProbe()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

_G.ADSDamageProbeActive = true

local HIT_WINDOW = 0.75
local WATCH_RADIUS = 700
local RESCAN_INTERVAL = 1.5
local MAX_LOGGED_SHOTS = 300

local connections = {}
local watchedHumanoids = {}
local recentShots = {}
local shotCount = 0
local adsHeld = false

local function log(message)
    print("[ADSDamageProbe] " .. tostring(message))
end

local function addConnection(connection)
    table.insert(connections, connection)
    return connection
end

local function getRoot(model)
    return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function getLocalRoot()
    return getRoot(LocalPlayer.Character)
end

local function getEquippedTool()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end

    return nil
end

local function readPossibleAttribute(instances, names)
    for _, instance in ipairs(instances) do
        if instance then
            for _, name in ipairs(names) do
                local value = instance:GetAttribute(name)
                if value ~= nil then
                    return value, name
                end
            end
        end
    end

    return nil, nil
end

local function inferADS()
    local character = LocalPlayer.Character
    local tool = getEquippedTool()
    local attrValue, attrName = readPossibleAttribute({ character, tool, LocalPlayer }, {
        "Aiming",
        "ADS",
        "Aimed",
        "Scoping",
        "Scoped",
        "RightClick",
        "MouseLocked",
    })

    if type(attrValue) == "boolean" then
        return attrValue or adsHeld, attrName
    end

    return adsHeld or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2), "MouseButton2"
end

local function getItemDatabaseEntry(tool)
    if not tool then
        return nil
    end

    local mods = ReplicatedStorage:FindFirstChild("Mods")
    local itemDatabaseModule = mods and mods:FindFirstChild("ItemDatabase")
    if not itemDatabaseModule then
        return nil
    end

    local ok, itemDatabase = pcall(require, itemDatabaseModule)
    if not ok or type(itemDatabase) ~= "table" then
        return nil
    end

    return itemDatabase[tool.Name]
        or itemDatabase[tool:GetAttribute("ItemName")]
        or itemDatabase[tool:GetAttribute("ID")]
end

local function readStatFromTool(tool, statName)
    if not tool then
        return nil
    end

    local attr = tool:GetAttribute(statName)
    if type(attr) == "number" then
        return attr
    end

    for _, descendant in ipairs(tool:GetDescendants()) do
        local value = descendant:GetAttribute(statName)
        if type(value) == "number" then
            return value
        end
    end

    return nil
end

local function getWeaponStats()
    local tool = getEquippedTool()
    local databaseEntry = getItemDatabaseEntry(tool)
    local stats = databaseEntry and databaseEntry.Stats

    local function stat(name)
        local fromTool = readStatFromTool(tool, name)
        if type(fromTool) == "number" then
            return fromTool
        end

        if type(stats) == "table" and type(stats[name]) == "number" then
            return stats[name]
        end

        if type(databaseEntry) == "table" and type(databaseEntry[name]) == "number" then
            return databaseEntry[name]
        end

        return nil
    end

    return {
        Tool = tool and tool.Name or "None",
        Spread = stat("Spread"),
        AimedSpread = stat("AimedSpread"),
        Recoil = stat("Recoil"),
        Kickback = stat("Kickback"),
        AimedKickback = stat("AimedKickback"),
        MaxRange = stat("MaxRange"),
        DamageDropOff = stat("DamageDropOff"),
    }
end

local function addModelsFromFolder(folder, targets)
    if not folder then
        return
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then
            table.insert(targets, child)
        elseif child:IsA("Folder") then
            addModelsFromFolder(child, targets)
        end
    end
end

local function collectTargets()
    local targets = {}
    addModelsFromFolder(Workspace:FindFirstChild("NPCs"), targets)
    return targets
end

local function getNearestTarget()
    local localRoot = getLocalRoot()
    if not localRoot then
        return nil, math.huge
    end

    local bestTarget = nil
    local bestDistance = math.huge

    for _, target in ipairs(collectTargets()) do
        local humanoid = target:FindFirstChildOfClass("Humanoid") or target:FindFirstChild("Humanoid")
        local root = getRoot(target)

        if humanoid and humanoid.Health > 0 and root then
            local distance = (root.Position - localRoot.Position).Magnitude
            if distance < bestDistance and distance <= WATCH_RADIUS then
                bestTarget = target
                bestDistance = distance
            end
        end
    end

    return bestTarget, bestDistance
end

local function describeStats(stats)
    return string.format(
        "tool=%s spread=%s aimedSpread=%s recoil=%s kick=%s aimedKick=%s maxRange=%s dropOff=%s",
        tostring(stats.Tool),
        tostring(stats.Spread),
        tostring(stats.AimedSpread),
        tostring(stats.Recoil),
        tostring(stats.Kickback),
        tostring(stats.AimedKickback),
        tostring(stats.MaxRange),
        tostring(stats.DamageDropOff)
    )
end

local function recordShot()
    shotCount += 1
    if shotCount > MAX_LOGGED_SHOTS then
        table.remove(recentShots, 1)
    end

    local ads, adsSource = inferADS()
    local stats = getWeaponStats()
    local target, distance = getNearestTarget()

    local shot = {
        Id = shotCount,
        Time = os.clock(),
        ADS = ads,
        ADSSource = adsSource,
        Tool = stats.Tool,
        Target = target,
        Distance = distance,
        Hit = false,
    }

    table.insert(recentShots, shot)

    log(string.format(
        "SHOT #%d ads=%s source=%s target=%s dist=%.1f %s",
        shot.Id,
        tostring(ads),
        tostring(adsSource),
        target and target.Name or "nil",
        distance,
        describeStats(stats)
    ))
end

local function findRecentShotForTarget(model)
    local now = os.clock()

    for i = #recentShots, 1, -1 do
        local shot = recentShots[i]
        if now - shot.Time > HIT_WINDOW then
            break
        end

        if not shot.Hit and (shot.Target == model or not shot.Target) then
            return shot
        end
    end

    return nil
end

local function watchTarget(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("Humanoid")
    if not humanoid or watchedHumanoids[humanoid] then
        return
    end

    watchedHumanoids[humanoid] = humanoid.Health

    addConnection(humanoid.HealthChanged:Connect(function(newHealth)
        local oldHealth = watchedHumanoids[humanoid] or newHealth
        watchedHumanoids[humanoid] = newHealth

        if newHealth >= oldHealth then
            return
        end

        local shot = findRecentShotForTarget(model)
        if shot then
            shot.Hit = true
            log(string.format(
                "DAMAGE shot#%d ads=%s target=%s damage=%.1f dist=%.1f",
                shot.Id,
                tostring(shot.ADS),
                model.Name,
                oldHealth - newHealth,
                shot.Distance
            ))
        else
            log(string.format(
                "DAMAGE unmatched target=%s damage=%.1f",
                model.Name,
                oldHealth - newHealth
            ))
        end
    end))
end

addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        adsHeld = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not gameProcessed then
        recordShot()
    end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        adsHeld = false
    end
end))

task.spawn(function()
    log("Started. Shoot the same NPC with ADS and hip-fire, then compare DAMAGE lines.")

    while _G.ADSDamageProbeActive do
        for _, target in ipairs(collectTargets()) do
            watchTarget(target)
        end

        task.wait(RESCAN_INTERVAL)
    end
end)

_G.StopADSDamageProbe = function()
    _G.ADSDamageProbeActive = false

    for _, connection in ipairs(connections) do
        if typeof(connection) == "RBXScriptConnection" and connection.Connected then
            connection:Disconnect()
        end
    end

    table.clear(connections)
    table.clear(watchedHumanoids)
    table.clear(recentShots)
    log("Stopped.")
end
