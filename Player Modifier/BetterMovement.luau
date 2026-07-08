--[[
    ========================================================================
    Player Modifier - BetterMovement Module (Inertia & Penalty Bypasser)
    ========================================================================
    This module implements fine-grained movement modifications:
        1. "Better Movement" -> Eliminates inertia/sliding on RenderStepped.
        2. "No Slowdown Aim" -> Removes movement speed penalties when aiming.
        3. "No Slowdown Block" -> Removes speed penalties when blocking or using items.
        4. "No Slowdown OverWeight" -> Removes speed penalties when carrying too much weight.
        5. "No Slowdown Broken Leg/Arm" -> Hooks limb attributes to ignore bone fracture slowdowns.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local UPDATE_INTERVAL = 0.05
local NO_INERTIA_BIND_NAME = "BlackoutBetterMovementNoInertia"

local BetterMovement = {}
BetterMovement.Name = "Better Movement Logic"
BetterMovement.Description = "Removes inertia, penalties (Aiming/Reloading/Blocking), and leg crippling movement limits."

-- Helper to safely log messages
local function log(msg)
    print("[Player Modifier - BetterMovement] " .. tostring(msg))
end

local function getRuntime()
    _G.ModifierRuntime = _G.ModifierRuntime or {}
    _G.ModifierRuntime.BetterMovement = _G.ModifierRuntime.BetterMovement or {}
    return _G.ModifierRuntime.BetterMovement
end

local function getOptions()
    if not _G.ModifierStates then
        return nil
    end

    _G.ModifierStates.BetterMovementOptions = _G.ModifierStates.BetterMovementOptions or {}
    return _G.ModifierStates.BetterMovementOptions
end

local function optionEnabled(optionName)
    local options = getOptions()
    return options and options[optionName] == true
end

local function getRawCharacterStates()
    local runtime = getRuntime()
    return runtime.RawCharacterStates or rawget(_G, "CharacterStates")
end

local function setStateValue(states, key, value)
    if type(states) ~= "table" then
        return
    end

    pcall(function()
        states[key] = value
    end)
end

local function sanitizeStateRead(source, key)
    if optionEnabled("Better Movement") and key == "NoSlide" then
        return true
    end

    if optionEnabled("No Slowdown Aim") and key == "AimingMovementSpeed" then
        return nil
    end

    if optionEnabled("No Slowdown Block")
        and (key == "Blocking" or key == "ServerBlocking") then
        return false
    end

    if optionEnabled("No Slowdown OverWeight") and key == "OverWeightCapacity" then
        return 0
    end

    if optionEnabled("No Slowdown Broken Leg/Arm") and key == "Crippled" then
        return nil
    end

    return source and source[key]
end

local function sanitizeStateWrite(source, key, value)
    if optionEnabled("Better Movement") and key == "NoSlide" then
        source[key] = true
        return
    end

    if optionEnabled("No Slowdown Aim") and key == "AimingMovementSpeed" then
        source[key] = nil
        return
    end

    if optionEnabled("No Slowdown Block")
        and (key == "Blocking" or key == "ServerBlocking") then
        source[key] = false
        return
    end

    if optionEnabled("No Slowdown OverWeight") and key == "OverWeightCapacity" then
        source[key] = 0
        return
    end

    if optionEnabled("No Slowdown Broken Leg/Arm") and key == "Crippled" then
        source[key] = nil
        return
    end

    source[key] = value
end

-- 1. No Inertia (Bypasses MovementHandler direction interpolation)
local function setupNoInertia()
    local runtime = getRuntime()
    if runtime.NoInertiaBound then
        return
    end

    runtime.NoInertiaBound = true

    pcall(function()
        RunService:UnbindFromRenderStep(NO_INERTIA_BIND_NAME)
    end)

    RunService:BindToRenderStep(NO_INERTIA_BIND_NAME, Enum.RenderPriority.Character.Value + 100, function()
        if not optionEnabled("Better Movement") then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        -- If character is moving, force input direction to bypass inertia lerp
        if humanoid and humanoid.MoveDirection.Magnitude > 0 then
            humanoid:Move(humanoid.MoveDirection)
        end
    end)

    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, {
            Destroy = function()
                pcall(function()
                    RunService:UnbindFromRenderStep(NO_INERTIA_BIND_NAME)
                end)
                runtime.NoInertiaBound = false
            end
        })
    end

    log("Instant direction controller registered.")
end

local function clearBrokenBoneAttributes(character)
    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:GetAttribute("BrokenBone") ~= nil then
            descendant:SetAttribute("BrokenBone", false)
        end
    end
end

local function sanitizeCurrentStates()
    local states = getRawCharacterStates()

    if optionEnabled("Better Movement") then
        setStateValue(states, "NoSlide", true)
    end

    if optionEnabled("No Slowdown Aim") then
        setStateValue(states, "AimingMovementSpeed", nil)
    end

    if optionEnabled("No Slowdown Block") then
        setStateValue(states, "Blocking", false)
        setStateValue(states, "ServerBlocking", false)
    end

    if optionEnabled("No Slowdown OverWeight") then
        setStateValue(states, "OverWeightCapacity", 0)
    end

    if optionEnabled("No Slowdown Broken Leg/Arm") then
        setStateValue(states, "Crippled", nil)
        clearBrokenBoneAttributes(LocalPlayer.Character)
    end
end

local function createStatesProxy(source)
    local proxy = setmetatable({}, {
        __isBetterMovementStatesProxy = true,
        __index = function(_, k)
            return sanitizeStateRead(source, k)
        end,
        __newindex = function(_, k, v)
            sanitizeStateWrite(source, k, v)
        end,
        __pairs = function()
            return pairs(source)
        end
    })

    return proxy
end

-- Intercept and proxy _G.CharacterStates assignments
local function setupStatesProxy()
    local runtime = getRuntime()
    if runtime.ProxyInstalled then
        return
    end

    runtime.ProxyInstalled = true
    runtime.RawCharacterStates = rawget(_G, "CharacterStates") or {}
    runtime.StatesProxy = createStatesProxy(runtime.RawCharacterStates)

    local mt = getmetatable(_G) or {}
    if mt.__isProxy and not mt.__betterMovementProxy then
        -- Older BetterMovement builds installed a partial _G.__newindex proxy that
        -- never saw CharacterStates updates once the raw key already existed.
        mt = {}
    end

    runtime.OldGlobalMetatable = mt
    runtime.OldGlobalIndex = mt.__index
    runtime.OldGlobalNewIndex = mt.__newindex

    mt.__isProxy = true
    mt.__betterMovementProxy = true

    local oldIndex = mt.__index
    local oldNewIndex = mt.__newindex

    mt.__index = function(t, key)
        if key == "CharacterStates" then
            return runtime.StatesProxy
        end

        if type(oldIndex) == "function" then
            return oldIndex(t, key)
        elseif type(oldIndex) == "table" then
            return oldIndex[key]
        end

        return nil
    end

    mt.__newindex = function(t, key, val)
        if key == "CharacterStates" and type(val) == "table" then
            runtime.RawCharacterStates = val
            runtime.StatesProxy = createStatesProxy(val)
            return
        end

        if type(oldNewIndex) == "function" then
            oldNewIndex(t, key, val)
        elseif type(oldNewIndex) == "table" then
            oldNewIndex[key] = val
        else
            rawset(t, key, val)
        end
    end

    rawset(_G, "CharacterStates", nil)
    setmetatable(_G, mt)
    log("Installed live _G.CharacterStates proxy.")
end

local function setupStateSanitizer()
    local runtime = getRuntime()
    if runtime.StateSanitizerThread then
        return
    end

    local sanitizerThread = task.spawn(function()
        while _G.ModifierStates do
            sanitizeCurrentStates()

            local delayTime = UPDATE_INTERVAL
            if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                delayTime = _G.PerformanceGuard.GetDelay(delayTime, "light")
            end

            task.wait(delayTime)
        end
    end)

    runtime.StateSanitizerThread = sanitizerThread

    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, sanitizerThread)
    end

    log("Movement state sanitizer registered.")
end

local function restoreOldBrokenProxyIfNeeded()
    local runtime = getRuntime()
    local mt = getmetatable(_G)

    if mt and mt.__betterMovementProxy and runtime.OldGlobalIndex == nil and runtime.OldGlobalNewIndex == nil then
        return
    end

    -- Older versions left CharacterStates as a raw key, which prevents __newindex
    -- from seeing the game's per-frame CharacterStates assignments.
    if rawget(_G, "CharacterStates") ~= nil and runtime.ProxyInstalled then
        rawset(_G, "CharacterStates", nil)
    end
end

function BetterMovement.RestoreGlobalProxy()
    local runtime = _G.ModifierRuntime and _G.ModifierRuntime.BetterMovement
    if not runtime or not runtime.ProxyInstalled then
        return
    end

    pcall(function()
        RunService:UnbindFromRenderStep(NO_INERTIA_BIND_NAME)
    end)

    local mt = getmetatable(_G)
    if mt and mt.__betterMovementProxy then
        mt.__index = runtime.OldGlobalIndex
        mt.__newindex = runtime.OldGlobalNewIndex
        mt.__betterMovementProxy = nil
        mt.__isProxy = nil

        if next(mt) == nil then
            setmetatable(_G, nil)
        else
            setmetatable(_G, mt)
        end
    end

    if runtime.RawCharacterStates then
        rawset(_G, "CharacterStates", runtime.RawCharacterStates)
    end

    runtime.ProxyInstalled = false
end

function BetterMovement:Init(UIRef)
    _G.ModifierConnections = _G.ModifierConnections or {}
    getOptions()

    setupStatesProxy()
    restoreOldBrokenProxyIfNeeded()
    setupStateSanitizer()
    setupNoInertia()

    local runtime = getRuntime()
    if not runtime.CleanupHandleAdded then
        runtime.CleanupHandleAdded = true
        table.insert(_G.ModifierConnections, {
            Destroy = function()
                BetterMovement.RestoreGlobalProxy()
            end
        })
    end

    log("Better Movement module initialized.")
end

return BetterMovement
