--[[
    ========================================================================
    Aim Assist Mode - Silent Aim Module (FastCast Target Homing)
    ========================================================================
    This module implements Silent Aim by hooking the game's FastCast projectile
    engine and injecting Homing TargetInformation.
    
    This ensures the bullet dynamically bends towards the target using native 
    game code, making the redirection completely legitimate to the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SilentAim = {}
SilentAim.Name = "Silent Aim Mode"
SilentAim.Description = "Injects native target homing parameters into fired bullets to redirect paths cleanly."

-- Helper to safely log messages
local function log(msg)
    print("[Aim Assist - SilentAim] " .. tostring(msg))
end

local function getTargetBone(targetCharacter)
    local targetPartName = _G.AimAssistStates and _G.AimAssistStates.TargetPart or "Head"
    if targetPartName == "Head" then
        return targetCharacter:FindFirstChild("Head")
            or targetCharacter:FindFirstChild("HumanoidRootPart")
            or targetCharacter:FindFirstChild("UpperTorso")
    end

    return targetCharacter:FindFirstChild("Torso")
        or targetCharacter:FindFirstChild("UpperTorso")
        or targetCharacter:FindFirstChild("HumanoidRootPart")
        or targetCharacter:FindFirstChild("Head")
end

local function injectTargetInformation(activeCast)
    if not activeCast or not activeCast.UserData then
        return
    end

    if not (_G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive) then
        return
    end

    if not _G.GetClosestAimTarget then
        return
    end

    local targetCharacter = _G.GetClosestAimTarget()
    if not targetCharacter then
        return
    end

    local targetBone = getTargetBone(targetCharacter)
    if not targetBone then
        return
    end

    activeCast.UserData.TargetInformation = {
        Object = targetBone,
        Distance = math.max((_G.AimAssistStates.FOVRadius or 100) * 3, 250),
        Lerp = {
            Min = 1,
            Max = 1,
        },
        Deadzone = -1,
        KeepVelocity = true,
        TurningDrag = false,
    }

    log("Injected homing data for bullet: " .. tostring(targetCharacter.Name))
end

-- Hook FastCast.Fire function to inject homing data
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

            injectTargetInformation(activeCast)
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

    -- Establish native weapon hook
    setupFastCastHook()
end

return SilentAim
