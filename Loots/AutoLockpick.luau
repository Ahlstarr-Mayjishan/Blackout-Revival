--[[
    ========================================================================
    Loots - Auto Lockpick
    ========================================================================
    Solves the client-side lockpick minigame.

    Modes:
    - Legit: humanized delay and local minigame control pulses before success.
    - Blatant: near-instant success result.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

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

local function getMinigamesGui()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    return playerGui and playerGui:FindFirstChild("Minigames")
end

local function getMinigamesModuleContainer()
    local minigamesGui = getMinigamesGui()
    local handler = minigamesGui and minigamesGui:FindFirstChild("MinigameHandler")
    return handler and handler:FindFirstChild("Minigames")
end

local function setCharacterMinigameState(active)
    local character = LocalPlayer.Character
    if not character then
        return
    end

    pcall(function()
        character:SetAttribute("DP", active)
        character:SetAttribute("NL", active)
    end)
end

local function hideMinigameUi()
    local minigamesGui = getMinigamesGui()
    local minigameState = minigamesGui and minigamesGui:FindFirstChild("MinigameState")
    if minigameState then
        pcall(function()
            minigameState.Visible = false
        end)
    end

    pcall(function()
        local dof = Lighting:FindFirstChild("DoF")
        if dof then
            dof.FarIntensity = 0
        end
    end)

    setCharacterMinigameState(false)
end

local function parkLockpickModel()
    local minigamesContainer = getMinigamesModuleContainer()
    local lockpick = Workspace:FindFirstChild("Lockpick")

    if not lockpick or not minigamesContainer then
        return
    end

    pcall(function()
        local lock = lockpick:FindFirstChild("Lock")
        local lockPart = lock and lock:FindFirstChild("Lock")
        if lockPart and type(lockPart.RemoveTag) == "function" then
            lockPart:RemoveTag("Interactable")
        end
    end)

    pcall(function()
        lockpick.Parent = minigamesContainer
    end)
end

local function fireLocalCancelCleanup()
    local controls = getMinigameControls()
    if controls and type(controls.Fire) == "function" then
        pcall(function()
            controls:Fire(Enum.KeyCode.E, "Began")
        end)

        task.wait(0.03)

        pcall(function()
            controls:Fire(Enum.KeyCode.E, "Ended")
        end)
    end

    task.wait(0.08)
    hideMinigameUi()
    parkLockpickModel()
end

local function forceClientMinigameCleanup(mode)
    if mode == "Legit" then
        fireLocalCancelCleanup()
        return
    end

    hideMinigameUi()
    parkLockpickModel()
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
        return (_G.LootStates and _G.LootStates.AutoLockpickBlatantDelay) or 0
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
    if not _G.LootStates or not _G.LootStates.AutoLockpick then
        return
    end

    _G.LootRuntime = _G.LootRuntime or {}
    _G.LootRuntime.AutoLockpickActiveSolves = _G.LootRuntime.AutoLockpickActiveSolves or {}
    local solveKey = tostring(minigameId)
    if _G.LootRuntime.AutoLockpickActiveSolves[solveKey] then
        return
    end
    _G.LootRuntime.AutoLockpickActiveSolves[solveKey] = true

    local _, minigameResult = getLootEvents()
    if not minigameResult then
        _G.LootRuntime.AutoLockpickActiveSolves[solveKey] = nil
        warn("[Loots - AutoLockpick] Events.Loot.MinigameResult not found.")
        return
    end

    local mode = getMode()

    if not _G.LootStates or not _G.LootStates.AutoLockpick then
        _G.LootRuntime.AutoLockpickActiveSolves[solveKey] = nil
        return
    end

    if mode == "Legit" then
        playLegitInputPattern()
    end

    local delay = getDelayForMode(mode)
    if delay > 0 then
        task.wait(delay)
    end

    if not _G.LootStates or not _G.LootStates.AutoLockpick then
        _G.LootRuntime.AutoLockpickActiveSolves[solveKey] = nil
        return
    end

    pcall(function()
        minigameResult:FireServer(minigameId, true)
    end)

    if mode == "Legit" then
        task.wait(0.12)
    else
        task.wait(0.03)
    end

    forceClientMinigameCleanup(mode)

    log("Solved lockpick using " .. mode .. " mode. id=" .. tostring(minigameId) .. " kind=" .. tostring(minigameKind))
    task.delay(1, function()
        if _G.LootRuntime and _G.LootRuntime.AutoLockpickActiveSolves then
            _G.LootRuntime.AutoLockpickActiveSolves[solveKey] = nil
        end
    end)
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
