--[[
    ========================================================================
    Aim Assist Mode - Silent Aim Module (FastCast Target Homing)
    ========================================================================
    This module implements Silent Aim by hooking the game's FastCast projectile
    engine and injecting Homing TargetInformation.
    
    This ensures the bullet dynamically bends towards the target using native 
    game code, making the redirection completely legitimate to the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local SilentAim = {}
SilentAim.Name = "Silent Aim Mode"
SilentAim.Description = "Injects native target homing parameters into fired bullets to redirect paths cleanly."

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

-- Target Memory / Stickiness variables to maintain lock during high recoil or wall flickers
local lastTargetChar = nil
local lastTargetBone = nil
local lastTargetTime = 0

-- Build target information table for FastCast homing
local function buildTargetInformation()
    if not (_G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive) then
        return nil
    end

    if not _G.GetClosestAimTarget then
        return nil
    end

    local targetCharacter, targetPos = _G.GetClosestAimTarget()
    local targetBone = nil

    if targetCharacter then
        targetBone = getTargetBone(targetCharacter)
        if targetBone then
            lastTargetChar = targetCharacter
            lastTargetBone = targetBone
            lastTargetTime = os.clock()
        end
    else
        -- Target Memory Fallback: Reuse last target if within 0.3 seconds and target is still alive and nearby
        if lastTargetChar and lastTargetBone and (os.clock() - lastTargetTime < 0.3) then
            local localChar = LocalPlayer.Character
            if lastTargetChar.Parent and lastTargetChar:FindFirstChild("Humanoid") and lastTargetChar.Humanoid.Health > 0 then
                if localChar and localChar:FindFirstChild("HumanoidRootPart") and lastTargetChar:FindFirstChild("HumanoidRootPart") then
                    local dist = (lastTargetChar.HumanoidRootPart.Position - localChar.HumanoidRootPart.Position).Magnitude
                    -- Ensure they are still within a reasonable targeting distance
                    if dist <= 300 then
                        targetCharacter = lastTargetChar
                        targetBone = lastTargetBone
                    end
                end
            end
        end
    end

    if not targetCharacter or not targetBone then
        return nil
    end

    return {
        Object = targetBone,
        Distance = 9999, -- Maximize check radius to ensure homing math never fails distance clamps
        Lerp = {
            Min = 1.0, -- Force instant snap
            Max = 1.0,
        },
        Deadzone = -1, -- Disable angle restrictions
        KeepVelocity = true,
        TurningDrag = false,
    }, targetCharacter
end

-- Directly write to ActiveCast UserData (delayed to prevent game script overwrite)
local function injectTargetInformation(activeCast)
    if not activeCast or not activeCast.UserData then
        return
    end

    local targetInformation, targetCharacter = buildTargetInformation()
    if not targetInformation then
        return
    end

    activeCast.UserData.TargetInformation = targetInformation
    log("Injected homing data for bullet: " .. tostring(targetCharacter.Name))
end

-- Hook Melee/BulletHandler Fire
local function setupBulletHandlerHook()
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
        
        -- Dynamically search for the correct data argument table (holds Tool, Settings, Character)
        local bulletData = nil
        for i = 1, #args do
            local arg = args[i]
            if type(arg) == "table" and arg.Settings and (arg.Tool or arg.Character) then
                bulletData = arg
                break
            end
        end

        local targetInformation, targetCharacter = buildTargetInformation()
        if targetInformation then
            if bulletData then
                bulletData.TargetInformation = targetInformation
                log("Queued homing data for BulletHandler: " .. tostring(targetCharacter.Name))
            else
                log("Warning: BulletHandler config table not found in arguments. Relying on FastCast hook fallback.")
            end
        end

        return oldFire(unpack(args))
    end

    log("Hooked BulletHandler.Fire successfully.")
end

-- Hook FastCast.Fire function
local function setupFastCastHook()
    local modsFolder = ReplicatedStorage:WaitForChild("Mods", 5)
    local fastCastModule = modsFolder and modsFolder:WaitForChild("FastCast", 5)
    
    if not fastCastModule then
        warn("FastCast module folder not found. Homing hook disabled.")
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
        
        -- Hook the Fire constructor
        fastCastTable.Fire = function(casterInstance, origin, direction, velocity, behavior)
            local activeCast = oldFire(casterInstance, origin, direction, velocity, behavior)

            -- Double injection layers:
            -- 1. Instant injection
            injectTargetInformation(activeCast)
            -- 2. Deferred injection (bypasses game script overwriting UserData properties right after Fire() returns)
            task.defer(injectTargetInformation, activeCast)
            
            return activeCast
        end
        
        log("Hooked FastCast.Fire successfully.")
    else
        warn("Failed to require or hook FastCast module function.")
    end
end

function SilentAim:Init(Tab)
    -- Add the toggle to the UI
    Tab:CreateToggle({
        Name = "Enable Silent Aim (Homing Bullet)",
        CurrentValue = _G.AimAssistStates and _G.AimAssistStates.SilentAimActive or false,
        Flag = "AimAssist_SilentAimActive",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.SilentAimActive = Value
            end
            print("[Aim Assist - SilentAim] Silent Aim active state: " .. tostring(Value))
        end,
    })

    -- Establish native weapon hook (using BOTH layers for 100% redundancy)
    setupBulletHandlerHook()
    setupFastCastHook()
end

return SilentAim
