--[[
    ========================================================================
    Aim Assist Mode - Silent Aim Module (Direct Direction Redirection)
    ========================================================================
    This module implements Silent Aim by overriding the initial bullet trajectory
    direction and velocity vectors at the moment of firing.
    
    This provides lag-free, highly reliable hit registration by using the native
    bullet simulation path without hooking heavy Raycast methods.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local tableUnpack = table.unpack or unpack

local SilentAim = {}
SilentAim.Name = "Silent Aim"
SilentAim.Description = "Redirects bullet muzzle velocity directly towards targets on fire for lag-free, reliable hits."

-- Helper to safely log messages
local function log(msg)
    print("[Aim Assist - SilentAim] " .. tostring(msg))
end

-- Get target bone based on configuration with safety fallbacks
local function getTargetBone(targetCharacter)
    local targetPartName = _G.AimAssistStates and _G.AimAssistStates.TargetPart or "Head"
    if targetPartName == "Head" then
        return targetCharacter:FindFirstChild("Head")
            or targetCharacter:FindFirstChild("HumanoidRootPart")
            or targetCharacter.PrimaryPart
    end

    return targetCharacter:FindFirstChild("Torso")
        or targetCharacter:FindFirstChild("UpperTorso")
        or targetCharacter:FindFirstChild("HumanoidRootPart")
        or targetCharacter.PrimaryPart
end

-- Find target and return its position
local function getTargetPosition()
    if not (_G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive) then
        return nil
    end

    if not _G.GetClosestAimTarget then
        return nil
    end

    local targetCharacter, targetPos = _G.GetClosestAimTarget()
    if not targetCharacter then
        return nil
    end

    local targetBone = getTargetBone(targetCharacter)
    return targetBone and targetBone.Position
end

local function isDescendantOfLocalCharacter(instance)
    local character = LocalPlayer.Character
    return instance ~= nil
        and character ~= nil
        and typeof(instance) == "Instance"
        and (instance == character or instance:IsDescendantOf(character))
end

local function isLocalBulletData(bulletData)
    if type(bulletData) ~= "table" then
        return false
    end

    if bulletData.Character == LocalPlayer.Character then
        return true
    end

    if isDescendantOfLocalCharacter(bulletData.Tool)
        or isDescendantOfLocalCharacter(bulletData.GunModel)
        or isDescendantOfLocalCharacter(bulletData.Model)
        or isDescendantOfLocalCharacter(bulletData.Weapon) then
        return true
    end

    local owner = bulletData.Owner or bulletData.Player or bulletData.User
    return owner == LocalPlayer
end

local function findBulletData(args)
    local arg6 = args[6]
    if type(arg6) == "table" and arg6.Settings then
        return arg6
    end

    for _, arg in ipairs(args) do
        if type(arg) == "table" and arg.Settings then
            return arg
        end
    end

    return nil
end

local function shouldProcessBulletHandlerShot(args)
    return isLocalBulletData(findBulletData(args))
end

local function shouldProcessFastCastShot(casterInstance, behavior)
    if isDescendantOfLocalCharacter(casterInstance) then
        return true
    end

    if type(behavior) == "table" then
        return isLocalBulletData(behavior.UserData)
            or isLocalBulletData(behavior.Data)
            or isLocalBulletData(behavior.BulletData)
    end

    return false
end

-- Hook Melee/BulletHandler Fire
local function setupBulletHandlerHook()
    _G.AimAssistOriginals = _G.AimAssistOriginals or {}

    local gunStorage = ReplicatedStorage:WaitForChild("GunStorage", 5)
    local modsFolder = gunStorage and gunStorage:WaitForChild("Mods", 5)
    local bulletHandlerModule = modsFolder and modsFolder:WaitForChild("BulletHandler", 5)

    if not bulletHandlerModule then
        warn("BulletHandler module not found. Skipping BulletHandler hook.")
        return
    end

    local success, bulletHandler = pcall(require, bulletHandlerModule)
    if not (success and type(bulletHandler) == "table" and type(bulletHandler.Fire) == "function") then
        warn("Failed to require BulletHandler module.")
        return
    end

    if _G.AimAssistOriginals["BulletHandler_Fire"] then
        log("BulletHandler.Fire hook already setup.")
        return
    end

    local oldFire = bulletHandler.Fire
    _G.AimAssistOriginals["BulletHandler_Fire"] = oldFire

    bulletHandler.Fire = function(...)
        local args = {...}
        
        -- Override initial direction (arg 3) if target is visible
        if _G.AimAssistStates
            and _G.AimAssistStates.Enabled
            and _G.AimAssistStates.SilentAimActive
            and shouldProcessBulletHandlerShot(args) then
            local targetPos = getTargetPosition()
            if targetPos then
                local origin = args[2] -- arg 2 is origin
                if typeof(origin) == "Vector3" then
                    args[3] = (targetPos - origin).Unit -- Redirect direction vector
                    log("Redirected BulletHandler firing direction towards target.")
                end
            end
        end

        return oldFire(tableUnpack(args))
    end

    log("Hooked BulletHandler.Fire successfully.")
end

-- Hook FastCast.Fire function
local function setupFastCastHook()
    _G.AimAssistOriginals = _G.AimAssistOriginals or {}

    local modsFolder = ReplicatedStorage:WaitForChild("Mods", 5)
    local fastCastModule = modsFolder and modsFolder:WaitForChild("FastCast", 5)
    
    if not fastCastModule then
        warn("FastCast module folder not found. Skipping FastCast hook.")
        return
    end
    
    local success, fastCastTable = pcall(require, fastCastModule)
    if success and type(fastCastTable) == "table" and type(fastCastTable.Fire) == "function" then
        if _G.AimAssistOriginals["FastCast_Fire"] then
            log("FastCast.Fire hook already setup.")
            return
        end
        
        local oldFire = fastCastTable.Fire
        _G.AimAssistOriginals["FastCast_Fire"] = oldFire
        
        -- Hook the Fire constructor to override direction and velocity vectors
        fastCastTable.Fire = function(casterInstance, origin, direction, velocity, behavior)
            if _G.AimAssistStates
                and _G.AimAssistStates.Enabled
                and _G.AimAssistStates.SilentAimActive
                and shouldProcessFastCastShot(casterInstance, behavior) then
                local targetPos = getTargetPosition()
                if targetPos and typeof(origin) == "Vector3" then
                    direction = (targetPos - origin).Unit
                    if typeof(velocity) == "Vector3" then
                        velocity = direction * velocity.Magnitude
                    end
                    log("Redirected FastCast velocity and direction vectors towards target.")
                end
            end
            return oldFire(casterInstance, origin, direction, velocity, behavior)
        end
        
        log("Hooked FastCast.Fire successfully.")
    else
        warn("Failed to require or hook FastCast module function.")
    end
end

function SilentAim:Init(Tab)
    -- Add the toggle to the UI
    Tab:CreateToggle({
        Name = "Enable Silent Aim (Direct)",
        CurrentValue = _G.AimAssistStates and _G.AimAssistStates.SilentAimActive or false,
        Flag = "AimAssist_SilentAimActive",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.SilentAimActive = Value
            end
            print("[Aim Assist - SilentAim] Silent Aim active state: " .. tostring(Value))
        end,
    })

    -- Hook firing methods directly (zero lag)
    setupBulletHandlerHook()
    setupFastCastHook()
end

return SilentAim
