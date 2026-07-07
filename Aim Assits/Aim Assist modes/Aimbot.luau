--[[
    ========================================================================
    Aim Assist Mode - Aimbot Module (Camera Lock)
    ========================================================================
    This module implements a standard camera-locking aimbot that snaps and lerps
    the local player's view onto the acquired target.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Aimbot = {}
Aimbot.Name = "Aimbot Mode"
Aimbot.Description = "Locks and smoothly lerps the camera to targets inside the FOV circle when holding Right-Click."

function Aimbot:Init(Tab)
    -- Add the toggle to the UI
    Tab:CreateToggle({
        Name = "Enable Aimbot (Camera Lock)",
        CurrentValue = _G.AimAssistStates and _G.AimAssistStates.AimbotActive or false,
        Flag = "AimAssist_AimbotActive",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.AimbotActive = Value
            end
            print("[Aim Assist - Aimbot] Aimbot active state: " .. tostring(Value))
        end,
    })

    -- Background targeting and lock connection
    local connection = RunService.RenderStepped:Connect(function()
        if not _G.AimAssistStates or not _G.AimAssistStates.Enabled or not _G.AimAssistStates.AimbotActive then
            return
        end

        -- Check if target helper function is available
        if not _G.GetClosestAimTarget then
            return
        end

        local character = LocalPlayer.Character
        local isAimingHeld = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            or (_G.CharacterStates and _G.CharacterStates.Aiming == true)
            or (character and character:GetAttribute("InFirstPerson") == true and LocalPlayer:GetAttribute("MouseLocked") == true)

        if isAimingHeld then
            local Camera = Workspace.CurrentCamera
            if not Camera then
                return
            end

            local _, targetPos = _G.GetClosestAimTarget()
            if targetPos then
                local currentCFrame = Camera.CFrame
                local lookTarget = CFrame.new(currentCFrame.Position, targetPos)
                
                -- Smoothing factor calculation
                local smoothFactor = math.clamp(1 / (_G.AimAssistStates.Smoothing or 5), 0.01, 1)
                
                Camera.CFrame = currentCFrame:Lerp(lookTarget, smoothFactor)
            end
        end
    end)

    -- Register connection for GC cleanup
    if _G.AimAssistConnections then
        table.insert(_G.AimAssistConnections, connection)
    end

    print("[Aim Assist - Aimbot] Camera lock listener connected.")
end

return Aimbot
