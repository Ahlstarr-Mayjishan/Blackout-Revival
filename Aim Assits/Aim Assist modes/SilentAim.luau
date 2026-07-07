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
            -- Call original function to get the ActiveCast object returned by the game
            local activeCast = oldFire(casterInstance, origin, direction, velocity, behavior)
            
            -- If Silent Aim is active, inject the TargetInformation
            if _G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive then
                if _G.GetClosestAimTarget then
                    local targetCharacter, targetPos = _G.GetClosestAimTarget()
                    if targetCharacter and targetPos then
                        -- Find target bone part
                        local targetBone = targetCharacter:FindFirstChild(_G.AimAssistStates.TargetPart)
                        if not targetBone and _G.AimAssistStates.TargetPart == "Head" then
                            targetBone = targetCharacter:FindFirstChild("Head") or targetCharacter:FindFirstChild("PrimaryPart")
                        elseif not targetBone and _G.AimAssistStates.TargetPart == "Torso" then
                            targetBone = targetCharacter:FindFirstChild("Torso") or targetCharacter:FindFirstChild("UpperTorso") or targetCharacter:FindFirstChild("HumanoidRootPart")
                        end
                        
                        if targetBone then
                            -- Inject native homing target structure inside bullet UserData
                            activeCast.UserData.TargetInformation = {
                                Object = targetBone, -- Part instance target
                                Distance = _G.AimAssistStates.FOVRadius * 2, -- Target attraction threshold range
                                Lerp = {
                                    Min = 1.0, -- Force instant trajectory snap (100% precision)
                                    Max = 1.0
                                },
                                KeepVelocity = true,
                                TurningDrag = false
                            }
                            log("Injected homing data for bullet: " .. tostring(targetCharacter.Name))
                        end
                    end
                end
            end
            
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
