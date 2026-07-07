--[[
    ========================================================================
    Aim Assist Mode - Homing Bullets Module (FastCast Target Homing)
    ========================================================================
    This module implements Homing Bullets by injecting the game's native
    TargetInformation table before BulletHandler creates a FastCast bullet.
    
    It keeps the game's original RaycastParams/CanPierce path intact, which is
    more stable than replacing collision filters after the cast has started.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local tableUnpack = table.unpack or unpack
local BULLET_HANDLER_HOOK_KEY = "HomingBullets_BulletHandler_Fire"
local FASTCAST_HOOK_KEY = "HomingBullets_FastCast_Fire"

local HomingBullets = {}
HomingBullets.Name = "Homing Bullets"
HomingBullets.Description = "Bends the bullet trajectory dynamically to hit targets using native game physics. Supports sky-shot target acquisition."
local lastLogTime = 0

-- Helper to safely log messages
local function log(msg)
    local now = os.clock()
    if now - lastLogTime < 0.35 then
        return
    end
    lastLogTime = now
    print("[Aim Assist - HomingBullets] " .. tostring(msg))
end

local function isHomingEnabled()
    return _G.AimAssistStates
        and _G.AimAssistStates.Enabled
        and _G.AimAssistStates.HomingBulletsActive
end

-- Helper: Check if character is alive
local function isAlive(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
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

-- Get closest target in 3D space (regardless of screen FOV)
local function getClosestTarget3D()
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local localPos = localChar.HumanoidRootPart.Position
    local closestChar = nil
    local closestDist = 99999 -- Maximum range buffer
    
    local npcs = Workspace:FindFirstChild("NPCs")
    local chars = Workspace:FindFirstChild("Chars")
    local aimType = _G.AimAssistStates and _G.AimAssistStates.AimType or "Player"
    
    local targets = {}
    if aimType == "Zombie (Nightbounds)" and npcs then
        for _, group in ipairs(npcs:GetChildren()) do
            if group:IsA("Model") then
                table.insert(targets, group)
            elseif group:IsA("Folder") then
                for _, npc in ipairs(group:GetChildren()) do
                    if npc:IsA("Model") then
                        table.insert(targets, npc)
                    end
                end
            end
        end
    elseif aimType == "Player" and chars then
        for _, char in ipairs(chars:GetChildren()) do
            if char:IsA("Model") then
                table.insert(targets, char)
            end
        end
    end
    
    for _, child in ipairs(targets) do
        if child ~= localChar and isAlive(child) then
            local targetRoot = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
            if targetRoot then
                local dist = (targetRoot.Position - localPos).Magnitude
                if dist < closestDist then
                    closestChar = child
                    closestDist = dist
                end
            end
        end
    end
    
    return closestChar
end

-- Target Memory / Stickiness variables to maintain lock during high recoil or wall flickers
local lastTargetChar = nil
local lastTargetBone = nil
local lastTargetTime = 0

-- Build target information table for FastCast homing
local function buildTargetInformation()
    if not isHomingEnabled() then
        return nil
    end

    local targetCharacter = nil
    
    -- 1. Try to fetch standard screen FOV target first
    if _G.GetClosestAimTarget then
        targetCharacter = _G.GetClosestAimTarget()
    end
    
    -- 2. Fallback: Fetch closest target in 3D space (allows sky-shot homing)
    if not targetCharacter then
        targetCharacter = getClosestTarget3D()
    end
    
    local targetBone = nil

    if targetCharacter then
        targetBone = getTargetBone(targetCharacter)
        if targetBone then
            lastTargetChar = targetCharacter
            lastTargetBone = targetBone
            lastTargetTime = os.clock()
        end
    else
        -- 3. Memory Fallback: Reuse last target if within 0.3 seconds and target is still alive and nearby
        if lastTargetChar and lastTargetBone and (os.clock() - lastTargetTime < 0.3) then
            local localChar = LocalPlayer.Character
            if lastTargetChar.Parent and lastTargetChar:FindFirstChild("Humanoid") and lastTargetChar.Humanoid.Health > 0 then
                if localChar and localChar:FindFirstChild("HumanoidRootPart") and lastTargetChar:FindFirstChild("HumanoidRootPart") then
                    local dist = (lastTargetChar.HumanoidRootPart.Position - localChar.HumanoidRootPart.Position).Magnitude
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
        Distance = 9999, -- Keeps native homing lerp at full strength.
        Lerp = {
            Min = 1.0, -- Force instant snap
            Max = 1.0,
        },
        Deadzone = -1, -- Disable angle restrictions
        KeepVelocity = true,
        TurningDrag = false,
    }, targetCharacter
end

local function findBulletData(args)
    local arg6 = args[6]
    if type(arg6) == "table" and arg6.Settings then
        return arg6
    end

    for i = 1, #args do
        local arg = args[i]
        if type(arg) == "table" and arg.Settings and (arg.Tool or arg.Character or arg.GunModel) then
            return arg
        end
    end

    return nil
end

local function redirectInitialDirection(args, targetInformation)
    local origin = args[2]
    local targetObject = targetInformation and targetInformation.Object
    if typeof(origin) ~= "Vector3" or not targetObject then
        return
    end

    local delta = targetObject.Position - origin
    if delta.Magnitude <= 0 then
        return
    end

    -- BulletHandler.Fire expects p3 as a unit direction; the game multiplies it by MaxRange.
    args[3] = delta.Unit
end

-- Directly write to ActiveCast UserData as a fallback after BulletHandler creates the cast.
local function injectTargetInformation(activeCast)
    if not activeCast or not activeCast.UserData then
        return
    end

    local targetInformation, targetCharacter = buildTargetInformation()
    if not targetInformation then
        return
    end

    activeCast.UserData.TargetInformation = targetInformation

    log("Injected native homing data: " .. tostring(targetCharacter.Name))
end

-- Hook BulletHandler.Fire. Decompiled signature:
-- Fire(caster, origin, direction, shootId, bulletId, data)
-- The game later copies data.TargetInformation into activeCast.UserData.TargetInformation.
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

    if _G.AimAssistOriginals[BULLET_HANDLER_HOOK_KEY] then
        log("BulletHandler.Fire hook already setup.")
        return
    end

    local oldFire = bulletHandler.Fire
    _G.AimAssistOriginals[BULLET_HANDLER_HOOK_KEY] = oldFire

    bulletHandler.Fire = function(...)
        local args = {...}
        
        if isHomingEnabled() then
            local bulletData = findBulletData(args)
            local targetInformation, targetCharacter = buildTargetInformation()
            if bulletData and targetCharacter and targetInformation then
                if bulletData then
                    bulletData.TargetInformation = targetInformation
                end
                redirectInitialDirection(args, targetInformation)
                log("Queued native BulletHandler homing: " .. tostring(targetCharacter.Name))
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
        warn("FastCast module folder not found. Homing hook disabled.")
        return
    end
    
    local success, fastCastTable = pcall(require, fastCastModule)
    if success and type(fastCastTable) == "table" and type(fastCastTable.Fire) == "function" then
        if _G.AimAssistOriginals[FASTCAST_HOOK_KEY] then
            log("FastCast.Fire hook already setup.")
            return
        end
        
        local oldFire = fastCastTable.Fire
        _G.AimAssistOriginals[FASTCAST_HOOK_KEY] = oldFire
        
        -- Hook the Fire constructor as a fallback layer for casts created outside BulletHandler.
        fastCastTable.Fire = function(casterInstance, origin, direction, velocity, behavior)
            if isHomingEnabled() then
                local targetInformation, targetCharacter = buildTargetInformation()
                if targetCharacter and targetInformation and targetInformation.Object then
                    local targetPos = targetInformation.Object.Position
                    local delta = targetPos - origin
                    if delta.Magnitude > 0 then
                        local originalDistance = if typeof(direction) == "Vector3" then direction.Magnitude else delta.Magnitude
                        direction = delta.Unit * originalDistance

                        if typeof(velocity) == "Vector3" then
                            velocity = delta.Unit * velocity.Magnitude
                        end

                        log("Redirected FastCast initial vector: " .. tostring(targetCharacter.Name))
                    end
                end
            end

            local activeCast = oldFire(casterInstance, origin, direction, velocity, behavior)

            if isHomingEnabled() then
                injectTargetInformation(activeCast)
                task.defer(injectTargetInformation, activeCast)
            end
            
            return activeCast
        end
        
        log("Hooked FastCast.Fire successfully.")
    else
        warn("Failed to require or hook FastCast module function.")
    end
end

function HomingBullets:Init(Tab)
    -- Initialize state
    _G.AimAssistStates.HomingBulletsActive = _G.AimAssistStates.HomingBulletsActive or false

    -- Add the toggle to the UI
    Tab:CreateToggle({
        Name = "Enable Homing Bullets",
        CurrentValue = _G.AimAssistStates.HomingBulletsActive,
        Flag = "AimAssist_HomingBulletsActive",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.HomingBulletsActive = Value
            end
            print("[Aim Assist - HomingBullets] Homing Bullets active state: " .. tostring(Value))
        end,
    })

    -- Establish native weapon hook (using BOTH layers for 100% redundancy)
    setupBulletHandlerHook()
    setupFastCastHook()
end

return HomingBullets
