--[[
    ========================================================================
    Aim Assist Mode - Recoil Control
    ========================================================================
    Applies local weapon stat multipliers for recoil, kickback, and spread.

    100% = original value.
    0% = no local recoil/kickback/spread for the patched stat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local RecoilControl = {}
RecoilControl.Name = "Recoil Control"
RecoilControl.Description = "Adjusts local weapon recoil, kickback, and spread multipliers."

local PATCH_FIELDS = {
    Recoil = "RecoilMultiplier",
    Kickback = "KickbackMultiplier",
    AimedKickback = "KickbackMultiplier",
    Spread = "SpreadMultiplier",
    AimedSpread = "SpreadMultiplier",
}

local function log(message)
    print("[Aim Assist - RecoilControl] " .. tostring(message))
end

local function getMultiplier(stateKey)
    local states = _G.AimAssistStates
    local value = states and states[stateKey]
    if type(value) ~= "number" then
        return 1
    end

    return math.clamp(value, 0, 100) / 100
end

local function rememberOriginal(container, key, value)
    _G.AimAssistOriginals = _G.AimAssistOriginals or {}
    _G.AimAssistOriginals.RecoilControlStats = _G.AimAssistOriginals.RecoilControlStats or {}

    local originals = _G.AimAssistOriginals.RecoilControlStats
    originals[container] = originals[container] or {}

    if originals[container][key] == nil then
        originals[container][key] = value
    end
end

local function patchStatsTable(stats)
    if type(stats) ~= "table" then
        return
    end

    for fieldName, stateKey in pairs(PATCH_FIELDS) do
        local originalValue = stats[fieldName]
        if type(originalValue) == "number" then
            rememberOriginal(stats, fieldName, originalValue)
            stats[fieldName] = originalValue * getMultiplier(stateKey)
        end
    end
end

local function patchItemDatabase()
    local mods = ReplicatedStorage:FindFirstChild("Mods")
    local itemDatabaseModule = mods and mods:FindFirstChild("ItemDatabase")
    if not itemDatabaseModule then
        return
    end

    local ok, itemDatabase = pcall(require, itemDatabaseModule)
    if not ok or type(itemDatabase) ~= "table" then
        return
    end

    for _, itemData in pairs(itemDatabase) do
        if type(itemData) == "table" then
            patchStatsTable(itemData.Stats)
            patchStatsTable(itemData)
        end
    end
end

local function patchAttributes(instance)
    if not instance or not instance.Parent then
        return
    end

    for fieldName, stateKey in pairs(PATCH_FIELDS) do
        local value = instance:GetAttribute(fieldName)
        if type(value) == "number" then
            rememberOriginal(instance, fieldName, value)
            instance:SetAttribute(fieldName, value * getMultiplier(stateKey))
        end
    end
end

local function patchCharacterTools()
    local character = LocalPlayer.Character
    if not character then
        return
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            patchAttributes(child)
            for _, descendant in ipairs(child:GetDescendants()) do
                patchAttributes(descendant)
            end
        end
    end
end

local function restoreOriginals()
    local originals = _G.AimAssistOriginals and _G.AimAssistOriginals.RecoilControlStats
    if type(originals) ~= "table" then
        return
    end

    for container, values in pairs(originals) do
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

    _G.AimAssistOriginals.RecoilControlStats = nil
end

local function applyRecoilControl()
    restoreOriginals()

    if not _G.AimAssistStates or not _G.AimAssistStates.RecoilControlActive then
        return
    end

    patchItemDatabase()
    patchCharacterTools()
end

local function setupLoop()
    _G.AimAssistConnections = _G.AimAssistConnections or {}
    _G.AimAssistRuntime = _G.AimAssistRuntime or {}

    if _G.AimAssistRuntime.RecoilControlThread and coroutine.status(_G.AimAssistRuntime.RecoilControlThread) ~= "dead" then
        return
    end

    local thread = task.spawn(function()
        while _G.AimAssistStates do
            applyRecoilControl()
            task.wait(0.75)
        end
    end)

    _G.AimAssistRuntime.RecoilControlThread = thread
    table.insert(_G.AimAssistConnections, thread)
end

function RecoilControl:Init(UIRef)
    setupLoop()
    log("Initialized.")
end

return RecoilControl
