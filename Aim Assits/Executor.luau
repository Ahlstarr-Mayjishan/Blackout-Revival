--[[
    ========================================================================
    Aim Assits - Executor Module (Core Targeting & Physics Hook Engine)
    ========================================================================
    This module implements the core aim calculations, screen-to-world projection,
    raycast line-of-sight checks, and locks/lerps the camera to targets.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Executor = {}
Executor.Name = "Aiming Engine"
Executor.Description = "Internal math engine that manages target acquisition, FOV rendering, and camera smoothing."

-- Drawing FOV circle initialization
local FOVCircle = nil
local drawingSuccess, drawingErr = pcall(function()
    if Drawing and type(Drawing.new) == "function" then
        FOVCircle = Drawing.new("Circle")
        FOVCircle.Color = Color3.fromRGB(255, 84, 84)
        FOVCircle.Thickness = 1.5
        FOVCircle.NumSides = 64
        FOVCircle.Filled = false
        FOVCircle.Visible = false
    end
end)

if not drawingSuccess then
    warn("[Aim Assist - Executor] Vector drawing library (Drawing.new) not supported in this executor environment: " .. tostring(drawingErr))
end

-- Helper: Get target position of a character based on bone preference
local function getTargetPosition(character, partName)
    local targetPart = character:FindFirstChild(partName)
    if not targetPart and partName == "Head" then
        targetPart = character:FindFirstChild("Head") or character.PrimaryPart
    elseif not targetPart and partName == "Torso" then
        targetPart = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    end
    return targetPart and targetPart.Position
end

-- Helper: Check if character is alive
local function isAlive(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

-- Helper: Visibility (wall) check using camera viewport raycasting
local function checkWallVisibility(targetPos, character)
    local Camera = Workspace.CurrentCamera
    if not Camera then
        return false
    end

    local cameraPos = Camera.CFrame.Position
    local rayDirection = targetPos - cameraPos
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    raycastParams.IgnoreWater = true
    
    local raycastResult = Workspace:Raycast(cameraPos, rayDirection, raycastParams)
    
    return raycastResult == nil or raycastResult.Instance:IsDescendantOf(character)
end

local function getClosestTarget()
    if not _G.AimAssistStates or not _G.AimAssistStates.Enabled then
        return nil, nil
    end

    local Camera = Workspace.CurrentCamera
    if not Camera then
        return nil, nil
    end

    local viewportSize = Camera.ViewportSize
    local aimCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
    local closestCharacter = nil
    local closestDistance = _G.AimAssistStates.FOVRadius or 100
    local targetPosition = nil

    local foldersToScan = {}
    local aimType = _G.AimAssistStates.AimType or "Player"
    
    if aimType == "Zombie (Nightbounds)" then
        local npcs = Workspace:FindFirstChild("NPCs")
        if npcs then
            table.insert(foldersToScan, npcs)
        else
            table.insert(foldersToScan, Workspace)
        end
    else -- "Player"
        local chars = Workspace:FindFirstChild("Chars")
        if chars then
            table.insert(foldersToScan, chars)
        else
            table.insert(foldersToScan, Workspace)
        end
    end
    
    for _, folder in ipairs(foldersToScan) do
        local children = folder == Workspace and folder:GetChildren() or folder:GetDescendants()
        for _, child in ipairs(children) do
            if child:IsA("Model") and child ~= LocalPlayer.Character and isAlive(child) then
                -- Skip if target is inside the wrong group (when Workspace fallback is active)
                if aimType == "Player" and Workspace:FindFirstChild("NPCs") and child:IsDescendantOf(Workspace.NPCs) then
                    continue
                elseif aimType == "Zombie (Nightbounds)" and Workspace:FindFirstChild("Chars") and child:IsDescendantOf(Workspace.Chars) then
                    continue
                end
                
                -- Team check bypass (only relevant for players)
                local isAlly = false
                if _G.AimAssistStates.TeamCheck then
                    local player = Players:GetPlayerFromCharacter(child)
                    if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
                        isAlly = true
                    end
                end
                
                if not isAlly then
                    local pos = getTargetPosition(child, _G.AimAssistStates.TargetPart)
                    if pos then
                        -- Project target world location to viewport screen coordinates
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                        if onScreen then
                            local screenVec2 = Vector2.new(screenPos.X, screenPos.Y)
                            local distToCenter = (screenVec2 - aimCenter).Magnitude
                            
                            -- Target within FOV radius and closer than current best candidate
                            if distToCenter < closestDistance then
                                -- Wall/visibility check
                                local isVisible = true
                                if _G.AimAssistStates.WallCheck then
                                    isVisible = checkWallVisibility(pos, child)
                                end
                                
                                if isVisible then
                                    closestCharacter = child
                                    closestDistance = distToCenter
                                    targetPosition = pos
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return closestCharacter, targetPosition
end

-- Expose the target acquisition function globally
_G.GetClosestAimTarget = getClosestTarget

-- Initialize background update loop
function Executor:Init(UIRef)
    -- 1. FOV Circle Renderer (Update size and position relative to viewport)
    local fovConnection = RunService.RenderStepped:Connect(function()
        if FOVCircle then
            if _G.AimAssistStates and _G.AimAssistStates.Enabled and _G.AimAssistStates.ShowFOV then
                local camera = Workspace.CurrentCamera
                local viewportSize = camera and camera.ViewportSize or Vector2.new(0, 0)
                FOVCircle.Position = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
                FOVCircle.Radius = _G.AimAssistStates.FOVRadius or 100
                FOVCircle.Visible = true
            else
                FOVCircle.Visible = false
            end
        end
    end)

    -- Register connections for GC clean up
    if _G.AimAssistConnections then
        table.insert(_G.AimAssistConnections, fovConnection)
    end
    
    -- Expose FOVCircle pointer to global connection stack for clean deletion
    if _G.AimAssistConnections and FOVCircle then
        table.insert(_G.AimAssistConnections, FOVCircle)
    end

    print("[Aim Assist - Executor] Aim FOV loop established and _G.GetClosestAimTarget exposed.")
end

return Executor
