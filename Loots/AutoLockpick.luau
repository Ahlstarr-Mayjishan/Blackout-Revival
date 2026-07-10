--[[
    ========================================================================
    Loots - Auto Lockpick
    ========================================================================
    Solves the client-side lockpick minigame.

    Modes:
    - Legit: humanized delay and local minigame control pulses before success.
    - Blatant: near-instant success result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoLockpick = {}
AutoLockpick.Name = "Auto Lockpick"
AutoLockpick.Description = "Automatically solves lockpick minigames with Legit or Blatant mode."

local function log(message)
    print("[Loots - AutoLockpick] " .. tostring(message))
end

local function getLootEvents()
    local events = ReplicatedStorage:FindFirstChild("Events")
    local loot = events and events:FindFirstChild("Loot")

    return loot and loot:FindFirstChild("Minigame"),
        loot and loot:FindFirstChild("MinigameResult"),
        loot and loot:FindFirstChild("MinigameMistake")
end

local function getMinigameControls()
    return ReplicatedStorage:FindFirstChild("MinigameControls")
end

local function getMode()
    local mode = _G.LootStates and _G.LootStates.AutoLockpickMode
    if mode == "Blatant" then
        return "Blatant"
    end

    return "Legit"
end

local function getDelayForMode(mode)
    if mode == "Blatant" then
        return (_G.LootStates and _G.LootStates.AutoLockpickBlatantDelay) or 0.08
    end

    local baseDelay = (_G.LootStates and _G.LootStates.AutoLockpickLegitDelay) or 1.15
    return baseDelay + math.random(8, 35) / 100
end

local function pulseControl(keyCode, holdTime)
    local controls = getMinigameControls()
    if not controls or type(controls.Fire) ~= "function" then
        return
    end

    pcall(function()
        controls:Fire(keyCode, "Began")
    end)

    task.wait(holdTime or 0.06)

    pcall(function()
        controls:Fire(keyCode, "Ended")
    end)
end

local function playLegitInputPattern()
    pulseControl(Enum.KeyCode.A, 0.08)
    task.wait(math.random(8, 18) / 100)
    pulseControl(Enum.KeyCode.D, 0.08)
    task.wait(math.random(8, 18) / 100)
    pulseControl(Enum.KeyCode.F, 0.28)
end

local function solveLockpick(minigameId, minigameKind)
    local _, minigameResult = getLootEvents()
    if not minigameResult then
        warn("[Loots - AutoLockpick] Events.Loot.MinigameResult not found.")
        return
    end

    local mode = getMode()

    if mode == "Legit" then
        playLegitInputPattern()
    end

    task.wait(getDelayForMode(mode))

    if not _G.LootStates or not _G.LootStates.AutoLockpick then
        return
    end

    pcall(function()
        minigameResult:FireServer(minigameId, true)
    end)

    log("Solved lockpick using " .. mode .. " mode. id=" .. tostring(minigameId) .. " kind=" .. tostring(minigameKind))
end

local function setupListener()
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}

    if _G.LootRuntime.AutoLockpickConnection and _G.LootRuntime.AutoLockpickConnection.Connected then
        return
    end

    local minigameRemote = getLootEvents()
    if not minigameRemote then
        warn("[Loots - AutoLockpick] Events.Loot.Minigame not found.")
        return
    end

    local connection = minigameRemote.OnClientEvent:Connect(function(minigameId, minigameKind)
        if not _G.LootStates or not _G.LootStates.AutoLockpick then
            return
        end

        task.spawn(function()
            solveLockpick(minigameId, minigameKind)
        end)
    end)

    _G.LootRuntime.AutoLockpickConnection = connection
    table.insert(_G.LootConnections, connection)
    log("Listener connected.")
end

function AutoLockpick:Init(UIRef)
    setupListener()
end

return AutoLockpick
