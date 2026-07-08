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
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local tableUnpack = table.unpack or unpack
local BULLET_HANDLER_HOOK_KEY = "HomingBullets_BulletHandler_Fire"
local FASTCAST_HOOK_KEY = "HomingBullets_FastCast_Fire"
local ENABLE_FASTCAST_FALLBACK_HOOK = false
local ENABLE_CURVE_PROXY = false

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

local function hasClearLine(fromPos, toPos, targetCharacter)
    if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then
        return false
    end

    local delta = toPos - fromPos
    if delta.Magnitude <= 0 then
        return true
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { LocalPlayer.Character }
    raycastParams.IgnoreWater = true

    pcall(function()
        raycastParams.CollisionGroup = "RayCasts"
    end)

    local result = Workspace:Raycast(fromPos, delta, raycastParams)
    if not result then
        return true
    end

    return targetCharacter ~= nil and result.Instance:IsDescendantOf(targetCharacter)
end

local function hasClearLineToTargetPart(fromPos, toPos, targetPart, targetCharacter)
    if typeof(fromPos) ~= "Vector3" or typeof(toPos) ~= "Vector3" then
        return false
    end

    local delta = toPos - fromPos
    if delta.Magnitude <= 0 then
        return true
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { LocalPlayer.Character }
    raycastParams.IgnoreWater = true

    pcall(function()
        raycastParams.CollisionGroup = "RayCasts"
    end)

    local result = Workspace:Raycast(fromPos, delta, raycastParams)
    if not result then
        return false
    end

    if targetPart and (result.Instance == targetPart or result.Instance:IsDescendantOf(targetPart)) then
        return true
    end

    return targetCharacter ~= nil and result.Instance:IsDescendantOf(targetCharacter)
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
        addTargetModels(npcs, targets)
    elseif aimType == "Player" and chars then
        addTargetModels(chars, targets)
    end
    
    for _, child in ipairs(targets) do
        if child ~= localChar and isAlive(child) and not isIgnoredTarget(child) then
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

local function getPathDistance(points)
    local total = 0
    for i = 1, #points - 1 do
        total = total + (points[i + 1] - points[i]).Magnitude
    end
    return total
end

local function isClearPath(points, targetCharacter, targetPart)
    for i = 1, #points - 1 do
        local isFinalSegment = i == #points - 1
        local clear = if isFinalSegment
            then hasClearLineToTargetPart(points[i], points[i + 1], targetPart, targetCharacter)
            else hasClearLine(points[i], points[i + 1], nil)

        if not clear then
            return false
        end
    end

    return true
end

local function pickCurvePath(origin, targetBone, targetCharacter)
    if typeof(origin) ~= "Vector3" or not targetBone then
        return nil
    end

    local targetPos = targetBone.Position
    if hasClearLine(origin, targetPos, targetCharacter) then
        return nil
    end

    local distance = (targetPos - origin).Magnitude
    local lift = math.clamp(distance * 0.35, 28, 110)
    local side = math.clamp(distance * 0.24, 18, 85)
    local midpoint = origin:Lerp(targetPos, 0.5)
    local camera = Workspace.CurrentCamera
    local right = camera and camera.CFrame.RightVector or Vector3.new(1, 0, 0)
    local forward = camera and camera.CFrame.LookVector or (targetPos - origin).Unit
    local up = Vector3.new(0, 1, 0)

    local candidates = {
        midpoint + Vector3.new(0, lift, 0),
        midpoint + Vector3.new(0, lift * 0.65, 0) + right * side,
        midpoint + Vector3.new(0, lift * 0.65, 0) - right * side,
        origin:Lerp(targetPos, 0.35) + Vector3.new(0, lift, 0) + right * (side * 0.65),
        origin:Lerp(targetPos, 0.35) + Vector3.new(0, lift, 0) - right * (side * 0.65),
        origin:Lerp(targetPos, 0.65) + Vector3.new(0, lift, 0) + right * (side * 0.65),
        origin:Lerp(targetPos, 0.65) + Vector3.new(0, lift, 0) - right * (side * 0.65),
        midpoint + Vector3.new(0, lift * 0.5, 0) + forward * (side * 0.75),
        midpoint + Vector3.new(0, lift * 0.5, 0) - forward * (side * 0.75),
    }

    local approachDistance = math.clamp(distance * 0.14, 8, 32)
    local targetApproaches = {
        targetPos + up * approachDistance,
        targetPos + right * approachDistance,
        targetPos - right * approachDistance,
        targetPos + forward * approachDistance,
        targetPos - forward * approachDistance,
        targetPos + up * (approachDistance * 0.7) + right * (approachDistance * 0.7),
        targetPos + up * (approachDistance * 0.7) - right * (approachDistance * 0.7),
    }

    local bestPath = nil
    local bestDistance = math.huge

    for _, waypoint in ipairs(candidates) do
        local path = { origin, waypoint, targetPos }
        if isClearPath(path, targetCharacter, targetBone) then
            local pathDistance = getPathDistance(path)
            if pathDistance < bestDistance then
                bestDistance = pathDistance
                bestPath = { waypoint }
            end
        end
    end

    for _, approach in ipairs(targetApproaches) do
        local path = { origin, approach, targetPos }
        if isClearPath(path, targetCharacter, targetBone) then
            local pathDistance = getPathDistance(path)
            if pathDistance < bestDistance then
                bestDistance = pathDistance
                bestPath = { approach }
            end
        end
    end

    for i = 1, #candidates do
        for j = 1, #candidates do
            if i ~= j then
                local path = { origin, candidates[i], candidates[j], targetPos }
                if isClearPath(path, targetCharacter, targetBone) then
                    local pathDistance = getPathDistance(path)
                    if pathDistance < bestDistance then
                        bestDistance = pathDistance
                        bestPath = { candidates[i], candidates[j] }
                    end
                end
            end
        end
    end

    for _, waypoint in ipairs(candidates) do
        for _, approach in ipairs(targetApproaches) do
            local path = { origin, waypoint, approach, targetPos }
            if isClearPath(path, targetCharacter, targetBone) then
                local pathDistance = getPathDistance(path)
                if pathDistance < bestDistance then
                    bestDistance = pathDistance
                    bestPath = { waypoint, approach }
                end
            end
        end
    end

    -- Helps over low cover. A fully sealed route still needs piercing/ignore-collision.
    return bestPath or { candidates[1] }
end

local function createCurveProxy(origin, targetBone, targetCharacter)
    if not ENABLE_CURVE_PROXY then
        return nil
    end

    local path = pickCurvePath(origin, targetBone, targetCharacter)
    if not path or not path[1] then
        return nil
    end

    local proxy = Instance.new("Part")
    proxy.Name = "HomingCurveProxy"
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanTouch = false
    proxy.Transparency = 1
    proxy.Size = Vector3.new(0.25, 0.25, 0.25)
    proxy.Position = path[1]

    pcall(function()
        proxy.CanQuery = false
    end)

    proxy.Parent = Workspace
    Debris:AddItem(proxy, 3)

    return {
        Proxy = proxy,
        TargetBone = targetBone,
        TargetCharacter = targetCharacter,
        Path = path,
        PathIndex = 1,
        Waypoint = path[1],
        Phase = "Waypoint",
        CreatedAt = os.clock(),
    }
end

-- Build target information table for FastCast homing
local function buildTargetInformation(origin)
    if not isHomingEnabled() then
        return nil
    end

    local targetCharacter = nil
    
    -- 1. Try to fetch standard screen FOV target first
    if _G.GetClosestAimTarget then
        targetCharacter = _G.GetClosestAimTarget()
        if isIgnoredTarget(targetCharacter) then
            targetCharacter = nil
        end
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
            if lastTargetChar.Parent
                and not isIgnoredTarget(lastTargetChar)
                and lastTargetChar:FindFirstChild("Humanoid")
                and lastTargetChar.Humanoid.Health > 0 then
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

    local curveProxyData = createCurveProxy(origin, targetBone, targetCharacter)

    return {
        Object = curveProxyData and curveProxyData.Proxy or targetBone,
        Distance = 9999, -- Keeps native homing lerp at full strength.
        Lerp = {
            Min = 1.0, -- Force instant snap
            Max = 1.0,
        },
        Deadzone = -1, -- Disable angle restrictions
        KeepVelocity = true,
        TurningDrag = false,
        CurveProxyData = curveProxyData,
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

    local origin = activeCast.UserData and activeCast.UserData.Origin
    local targetInformation, targetCharacter = buildTargetInformation(origin)
    if not targetInformation then
        return
    end

    activeCast.UserData.TargetInformation = targetInformation

    log("Injected native homing data: " .. tostring(targetCharacter.Name))
end

local function cleanupCurveProxy(proxyData, lengthConnection, hitConnection, terminateConnection)
    if lengthConnection then
        lengthConnection:Disconnect()
    end
    if hitConnection then
        hitConnection:Disconnect()
    end
    if terminateConnection then
        terminateConnection:Disconnect()
    end
    if proxyData and proxyData.Proxy then
        proxyData.Proxy:Destroy()
    end
end

local function attachCurveController(casterInstance, activeCast)
    if not casterInstance or not activeCast or not activeCast.UserData then
        return
    end

    local targetInformation = activeCast.UserData.TargetInformation
    local proxyData = targetInformation and targetInformation.CurveProxyData
    if not proxyData or not proxyData.Proxy or not proxyData.TargetBone then
        return
    end

    local lengthConnection = nil
    local hitConnection = nil
    local terminateConnection = nil

    lengthConnection = casterInstance.LengthChanged:Connect(function(cast, lastPoint)
        if cast ~= activeCast then
            return
        end

        local proxy = proxyData.Proxy
        local targetBone = proxyData.TargetBone
        if not proxy or not proxy.Parent or not targetBone or not targetBone.Parent then
            cleanupCurveProxy(proxyData, lengthConnection, hitConnection, terminateConnection)
            return
        end

        local currentPos = lastPoint
        pcall(function()
            currentPos = cast:GetPosition()
        end)

        local targetPos = targetBone.Position
        if proxyData.Phase == "Waypoint" then
            local reachedWaypoint = (currentPos - proxyData.Waypoint).Magnitude <= 32
            local targetVisible = hasClearLine(currentPos, targetPos, proxyData.TargetCharacter)
            local timedOut = os.clock() - proxyData.CreatedAt > 0.45

            if reachedWaypoint and proxyData.Path and proxyData.PathIndex < #proxyData.Path then
                proxyData.PathIndex = proxyData.PathIndex + 1
                proxyData.Waypoint = proxyData.Path[proxyData.PathIndex]
            elseif reachedWaypoint or targetVisible or timedOut then
                proxyData.Phase = "Target"
            end
        end

        if proxyData.Phase == "Target" then
            proxy.Position = targetPos
        else
            proxy.Position = proxyData.Waypoint
        end
    end)

    hitConnection = casterInstance.RayHit:Connect(function(cast)
        if cast == activeCast then
            cleanupCurveProxy(proxyData, lengthConnection, hitConnection, terminateConnection)
        end
    end)

    if casterInstance.CastTerminating then
        terminateConnection = casterInstance.CastTerminating:Connect(function(cast)
            if cast == activeCast then
                cleanupCurveProxy(proxyData, lengthConnection, hitConnection, terminateConnection)
            end
        end)
    end

    task.delay(3, function()
        if proxyData.Proxy and proxyData.Proxy.Parent then
            cleanupCurveProxy(proxyData, lengthConnection, hitConnection, terminateConnection)
        end
    end)
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
            local targetInformation, targetCharacter = buildTargetInformation(args[2])
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
    if not ENABLE_FASTCAST_FALLBACK_HOOK then
        if _G.AimAssistOriginals and _G.AimAssistOriginals[FASTCAST_HOOK_KEY] then
            local modsFolder = ReplicatedStorage:FindFirstChild("Mods")
            local fastCastModule = modsFolder and modsFolder:FindFirstChild("FastCast")

            if fastCastModule then
                local success, fastCastTable = pcall(require, fastCastModule)
                if success and type(fastCastTable) == "table" then
                    fastCastTable.Fire = _G.AimAssistOriginals[FASTCAST_HOOK_KEY]
                    _G.AimAssistOriginals[FASTCAST_HOOK_KEY] = nil
                    log("Restored old FastCast fallback hook; using BulletHandler native TargetInformation only.")
                    return
                end
            end
        end

        log("FastCast fallback hook disabled; using BulletHandler native TargetInformation only.")
        return
    end

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
                local targetInformation, targetCharacter = buildTargetInformation(origin)
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

                if ENABLE_CURVE_PROXY then
                    task.defer(attachCurveController, casterInstance, activeCast)
                end
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
