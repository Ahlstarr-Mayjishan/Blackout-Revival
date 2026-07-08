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

local function normalizeName(name)
    return string.lower(tostring(name or "")):gsub("%s+", " ")
end

local function isIgnoredTarget(character)
    if not character then
        return true
    end

    local ignored = _G.AimAssistStates and _G.AimAssistStates.IgnoredTargetNames
    local normalizedName = normalizeName(character.Name)

    if type(ignored) == "table" then
        for name, enabled in pairs(ignored) do
            if enabled and normalizedName == normalizeName(name) then
                return true
            end
        end
    end

    return normalizedName == "drone" or normalizedName == "military guard"
end

local function addTargetModels(folder, targets)
    if not folder then
        return
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then
            table.insert(targets, child)
        elseif child:IsA("Folder") then
            addTargetModels(child, targets)
        end
    end
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
    
    -- Exclude all players and NPCs so they don't block visibility checks for each other
    local filterList = {LocalPlayer.Character, Camera}
    local charsFolder = Workspace:FindFirstChild("Chars")
    if charsFolder then table.insert(filterList, charsFolder) end
    local npcsFolder = Workspace:FindFirstChild("NPCs")
    if npcsFolder then table.insert(filterList, npcsFolder) end
    
    raycastParams.FilterDescendantsInstances = filterList
    raycastParams.IgnoreWater = true
    
    local raycastResult = Workspace:Raycast(cameraPos, rayDirection, raycastParams)
    
    return raycastResult == nil
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

    local targetsToScan = {}
    local aimType = _G.AimAssistStates.AimType or "Player"
    
    if aimType == "Zombie (Nightbounds)" then
        local npcs = Workspace:FindFirstChild("NPCs")
        if npcs then
            addTargetModels(npcs, targetsToScan)
        end
    else -- "Player"
        local chars = Workspace:FindFirstChild("Chars")
        if chars then
            for _, char in ipairs(chars:GetChildren()) do
                if char:IsA("Model") then
                    table.insert(targetsToScan, char)
                end
            end
        end
    end
    
    for _, child in ipairs(targetsToScan) do
        if child ~= LocalPlayer.Character and isAlive(child) and not isIgnoredTarget(child) then
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

    return closestCharacter, targetPosition
end

-- Expose the target acquisition function globally
_G.GetClosestAimTarget = getClosestTarget

-- Initialize background update loop
function Executor:Init(UIRef)
    _G.AimAssistRuntime = _G.AimAssistRuntime or {}
    if _G.AimAssistRuntime.FOVConnection and _G.AimAssistRuntime.FOVConnection.Connected then
        print("[Aim Assist - Executor] Aim FOV loop already established.")
        return
    end

    -- 1. FOV Circle Renderer (Update size and position relative to viewport)
    local fovConnection = RunService.RenderStepped:Connect(function()
        if _G.PerformanceGuard
            and type(_G.PerformanceGuard.ShouldRun) == "function"
            and not _G.PerformanceGuard.ShouldRun("AimAssistFOV", 1 / 30, "light") then
            return
        end

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

    _G.AimAssistRuntime.FOVConnection = fovConnection

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
