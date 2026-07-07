--[[
    ========================================================================
    Aim Assist Mode - Silent Aim Module (Direct Raycast Redirection)
    ========================================================================
    This module implements Silent Aim by hooking Roblox's Raycast methods and
    redirecting bullet trajectories directly to the target.
    
    This provides instant, highly reliable hit registration without physics turning
    delay (inertia) associated with homing bullet methods.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local SilentAim = {}
SilentAim.Name = "Silent Aim"
SilentAim.Description = "Redirects gun raycasts directly to targets inside the FOV for instant, reliable hits."

-- Helper to safely log messages
local function log(msg)
    print("[Aim Assist - SilentAim] " .. tostring(msg))
end

-- Establish Raycast redirection hook
local function setupRaycastHook()
    -- 1. Hook __namecall (covers self:Raycast calls in game scripts)
    if hookmetamethod then
        if _G.AimAssistOriginals["Raycast_Metatable"] then
            log("Metatable raycast hook already active.")
        else
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if method == "Raycast" and _G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive then
                    local args = {...}
                    local origin = args[1]
                    local direction = args[2]
                    local params = args[3]
                    
                    -- Match gun bullet raycasts via game collision group signature ("RayCasts")
                    if params and params.CollisionGroup == "RayCasts" then
                        if _G.GetClosestAimTarget then
                            local _, targetPos = _G.GetClosestAimTarget()
                            if targetPos then
                                -- Direct redirect: recalculate vector pointing straight to target
                                args[2] = (targetPos - origin).Unit * direction.Magnitude
                                return oldNamecall(self, unpack(args))
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end)
            
            _G.AimAssistOriginals["Raycast_Metatable"] = oldNamecall
            log("Hooked __namecall Raycast successfully.")
        end
    end

    -- 2. Hook Workspace.Raycast function directly (fallback/redundancy for some executors)
    if hookfunction then
        if _G.AimAssistOriginals["Raycast_Function"] then
            log("Direct function raycast hook already active.")
        else
            local oldFunc
            oldFunc = hookfunction(Workspace.Raycast, function(self, origin, direction, params)
                if _G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.SilentAimActive then
                    if params and params.CollisionGroup == "RayCasts" then
                        if _G.GetClosestAimTarget then
                            local _, targetPos = _G.GetClosestAimTarget()
                            if targetPos then
                                -- Direct redirect
                                direction = (targetPos - origin).Unit * direction.Magnitude
                            end
                        end
                    end
                end
                return oldFunc(self, origin, direction, params)
            end)
            
            _G.AimAssistOriginals["Raycast_Function"] = oldFunc
            log("Hooked Workspace.Raycast function successfully.")
        end
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

    -- Establish raycast hooking
    setupRaycastHook()
end

return SilentAim
