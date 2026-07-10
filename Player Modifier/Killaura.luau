--[[
    ========================================================================
    Player Modifier - Killaura Module (Legit & Blatant Auto-Swing Logic)
    ========================================================================
    This module implements Killaura for Melee combat, supporting Legit auto-swing
    and Blatant collision raycast redirection.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local tableUnpack = table.unpack or unpack
local cachedMeleeMain = nil
local cachedInputHandler = nil
local virtualInputManager = nil
local lastRaycastDebugAt = 0
local pendingSwingReleaseAt = 0

local Killaura = {}
Killaura.Name = "Killaura (Melee) Logic"
Killaura.Description = "Automates melee swings and redirects blade collision points directly to targets."

local function getModifierState(name, fallback)
    if not _G.ModifierStates then
        return fallback
    end

    local value = _G.ModifierStates[name]
    if value == nil then
        return fallback
    end

    return value
end

local lastDebugAt = 0
local function debugLog(message)
    if not getModifierState("KillauraDebug", false) then
        return
    end

    local now = os.clock()
    if now - lastDebugAt < 1 then
        return
    end

    lastDebugAt = now
    print("[Player Modifier - Killaura] " .. tostring(message))
end

local function findEquippedMelee(character)
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute("Tool") and child:FindFirstChild("MeleeStatus") then
            return child
        end
    end

    for _, child in ipairs(character:GetChildren()) do
        if (child:IsA("Tool") or child:IsA("RayValue")) and child:FindFirstChild("MeleeStatus") then
            return child
        end
    end

    return nil
end

local function getHumanoid(model)
    if not model then
        return nil
    end

    return model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("Humanoid")
end

local function getTargetPart(target)
    local hitAt = string.lower(tostring(getModifierState("KillauraHitAt", "head")))
    local targetPartName = (hitAt == "head" or hitAt == "neck") and "Head" or "Torso"
    return target:FindFirstChild(targetPartName)
        or target:FindFirstChild("UpperTorso")
        or target:FindFirstChild("LowerTorso")
        or target:FindFirstChild("HumanoidRootPart")
        or target:FindFirstChild("Head")
end

local function getTargetPoint(target)
    local hitAt = string.lower(tostring(getModifierState("KillauraHitAt", "head")))
    local head = target:FindFirstChild("Head")
    local torso = target:FindFirstChild("Torso")
        or target:FindFirstChild("UpperTorso")
        or target:FindFirstChild("HumanoidRootPart")
    local targetPart = getTargetPart(target)

    if hitAt == "neck" and head and torso then
        return head.Position:Lerp(torso.Position, 0.35), head
    end

    if hitAt == "head" and head then
        return head.Position, head
    end

    if hitAt == "torso" and torso then
        return torso.Position, torso
    end

    return targetPart and targetPart.Position, targetPart
end

local function isValidTarget(model, localChar)
    if not model or not model:IsA("Model") or model == localChar then
        return false
    end

    local humanoid = getHumanoid(model)
    local root = model:FindFirstChild("HumanoidRootPart") or getTargetPart(model)
    if not humanoid or not root then
        return false
    end

    if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
        return false
    end

    local player = Players:GetPlayerFromCharacter(model)
    if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
        return false
    end

    return true
end

local function scanTargets(folder, localChar, localPos, maxRange, bestTarget, bestDistance)
    if not folder then
        return bestTarget, bestDistance
    end

    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and isValidTarget(child, localChar) then
            local root = child:FindFirstChild("HumanoidRootPart") or getTargetPart(child)
            local dist = (root.Position - localPos).Magnitude
            if dist < bestDistance and dist <= maxRange then
                bestTarget = child
                bestDistance = dist
            end
        elseif child:IsA("Folder") then
            bestTarget, bestDistance = scanTargets(child, localChar, localPos, maxRange, bestTarget, bestDistance)
        end
    end

    return bestTarget, bestDistance
end

-- Scan for closest valid target inside melee range (15 studs)
local function getClosestMeleeTarget()
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
        return nil
    end

    local localPos = localChar.HumanoidRootPart.Position
    local closestTarget = nil
    local maxRange = getModifierState("KillauraRange", 30)
    local closestDist = maxRange

    local folders = {}
    local chars = Workspace:FindFirstChild("Chars")
    if chars then table.insert(folders, chars) end
    local npcs = Workspace:FindFirstChild("NPCs")
    if npcs then table.insert(folders, npcs) end
    if #folders == 0 then table.insert(folders, Workspace) end

    for _, folder in ipairs(folders) do
        closestTarget, closestDist = scanTargets(folder, localChar, localPos, maxRange, closestTarget, closestDist)
    end

    return closestTarget
end

local function getMeleeMain()
    if cachedMeleeMain then
        return cachedMeleeMain
    end

    pcall(function()
        local meleeStorage = ReplicatedStorage:FindFirstChild("MeleeStorage")
        local mods = meleeStorage and meleeStorage:FindFirstChild("Mods")
        local mainModule = mods and mods:FindFirstChild("Main")
        if mainModule then
            cachedMeleeMain = require(mainModule)
        end
    end)

    return cachedMeleeMain
end

local function getInputHandler()
    if cachedInputHandler ~= nil then
        return cachedInputHandler
    end

    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Mods")
        local inputModule = mods and mods:FindFirstChild("InputHandler")
        if inputModule then
            cachedInputHandler = require(inputModule)
        end
    end)

    if cachedInputHandler == nil then
        cachedInputHandler = false
    end

    return cachedInputHandler
end

local function getVirtualInputManager()
    if virtualInputManager ~= nil then
        return virtualInputManager
    end

    local ok, service = pcall(function()
        return game:GetService("VirtualInputManager")
    end)

    virtualInputManager = ok and service or false
    return virtualInputManager
end

local function releaseSwingInput()
    local inputHandler = getInputHandler()

    if inputHandler and type(inputHandler.HandleInput) == "function" then
        pcall(function()
            inputHandler.HandleInput(nil, nil, "Ended", "M1")
        end)
    end

    if type(mouse1release) == "function" then
        pcall(mouse1release)
    end

    local vim = getVirtualInputManager()
    local camera = Workspace.CurrentCamera
    if vim and camera then
        local viewport = camera.ViewportSize
        pcall(function()
            vim:SendMouseButtonEvent(viewport.X * 0.5, viewport.Y * 0.5, 0, false, game, 0)
        end)
    end
end

local function scheduleSwingRelease(holdTime)
    local releaseAt = os.clock() + (holdTime or 0.05)
    pendingSwingReleaseAt = math.max(pendingSwingReleaseAt, releaseAt)

    task.delay(holdTime or 0.05, function()
        if os.clock() + 0.01 < pendingSwingReleaseAt then
            return
        end

        pendingSwingReleaseAt = 0
        releaseSwingInput()
    end)
end

local function sendInputHandlerSwing(holdTime)
    local inputHandler = getInputHandler()
    if not inputHandler or type(inputHandler.HandleInput) ~= "function" then
        return false
    end

    local ok = pcall(function()
        inputHandler.HandleInput(nil, nil, "Began", "M1")
        scheduleSwingRelease(holdTime or 0.05)
    end)

    return ok
end

local function sendInputHandlerHeavySwing()
    local inputHandler = getInputHandler()
    if not inputHandler or type(inputHandler.HandleInput) ~= "function" then
        return false
    end

    local ok = pcall(function()
        inputHandler.HandleInput(nil, nil, "Ended", "Melee_heavy_attack")
    end)

    return ok
end

local function sendMouseSwing(holdTime)
    holdTime = holdTime or 0.05

    if type(mouse1press) == "function" and type(mouse1release) == "function" then
        mouse1press()
        scheduleSwingRelease(holdTime)
        return true
    end

    local vim = getVirtualInputManager()
    local camera = Workspace.CurrentCamera
    if not vim or not camera then
        return false
    end

    local viewport = camera.ViewportSize
    local x = viewport.X * 0.5
    local y = viewport.Y * 0.5

    local ok = pcall(function()
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        scheduleSwingRelease(holdTime)
    end)

    return ok
end

local function fireSwingRemote(holdTime)
    return false
end

local function fireHeavySwingRemote()
    return false
end

local function performSwing()
    local holdTime = math.clamp(getModifierState("KillauraSwingHold", 0.1), 0.03, 0.2)
    local swingType = tostring(getModifierState("KillauraSwingType", "Normal"))
    local meleeMain = getMeleeMain()

    if swingType == "Heavy" then
        if sendInputHandlerHeavySwing() then
            return true
        end

        if meleeMain and type(meleeMain.Swing) == "function" then
            local ok = pcall(function()
                meleeMain.Swing(nil, true)
            end)

            if ok then
                return true
            end
        end

        return fireHeavySwingRemote()
    end

    if sendInputHandlerSwing(holdTime) then
        return true
    end

    if meleeMain and type(meleeMain.Swing) == "function" then
        local ok = pcall(function()
            meleeMain.Swing(true)
            task.delay(holdTime, function()
                pcall(function()
                    meleeMain.Swing(false)
                end)
            end)
        end)

        if ok then
            return true
        end
    end

    if sendMouseSwing(holdTime) then
        return true
    end

    return fireSwingRemote(holdTime)
end

local function isLikelyMeleeRaycast(origin, params)
    if typeof(origin) ~= "Vector3" or not params or not params.FilterDescendantsInstances then
        return false
    end

    local char = LocalPlayer.Character
    local melee = findEquippedMelee(char)
    if not melee then
        return false
    end

    for _, descendant in ipairs(melee:GetDescendants()) do
        if descendant:IsA("Attachment") and descendant.Name == "DmgPoint" then
            if (descendant.WorldPosition - origin).Magnitude <= 10 then
                return true
            end
        elseif descendant:IsA("BasePart") and (descendant.Position - origin).Magnitude <= 10 then
            return true
        end
    end

    local root = char and char:FindFirstChild("HumanoidRootPart")
    return root and (root.Position - origin).Magnitude <= 8
end

local function shouldDebugRaycast()
    if not getModifierState("KillauraDebug", false) then
        return false
    end

    local now = os.clock()
    if now - lastRaycastDebugAt < 1 then
        return false
    end

    lastRaycastDebugAt = now
    return true
end

local function getRedirectedDirection(origin)
    local target = getClosestMeleeTarget()
    if not target then
        if shouldDebugRaycast() then
            print("[Player Modifier - Killaura] Raycast matched melee, but no target in range.")
        end
        return nil
    end

    local targetPoint, targetPart = getTargetPoint(target)
    if not targetPoint or not targetPart then
        return nil
    end

    if shouldDebugRaycast() then
        print("[Player Modifier - Killaura] Redirecting hitbox ray to " .. tostring(target.Name) .. "." .. tostring(targetPart.Name))
    end

    return targetPoint - origin
end

-- Establish Raycast redirection hook for Blatant Mode
local function setupRaycastHook()
    _G.OriginalFunctions = _G.OriginalFunctions or {}

    if hookmetamethod then
        if _G.OriginalFunctions["MeleeRaycast_Metatable"] then return end
        
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "Raycast" and _G.ModifierStates and _G.ModifierStates.Killaura and _G.ModifierStates.KillauraMode == "Blatant" and _G.ModifierStates.KillauraHitAt ~= "off" then
                local args = {...}
                local origin = args[1]
                local params = args[3]
                
                if isLikelyMeleeRaycast(origin, params) then
                    local redirectedDirection = getRedirectedDirection(origin)
                    if redirectedDirection then
                        args[2] = redirectedDirection
                        return oldNamecall(self, tableUnpack(args))
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        
        _G.OriginalFunctions["MeleeRaycast_Metatable"] = oldNamecall
        print("[Player Modifier - Killaura] Metatable raycast hook set up.")
        
    elseif hookfunction then
        if _G.OriginalFunctions["MeleeRaycast_Function"] then return end
        
        local oldFunc
        oldFunc = hookfunction(Workspace.Raycast, function(self, origin, direction, params)
            if _G.ModifierStates and _G.ModifierStates.Killaura and _G.ModifierStates.KillauraMode == "Blatant" and _G.ModifierStates.KillauraHitAt ~= "off" then
                if isLikelyMeleeRaycast(origin, params) then
                    local redirectedDirection = getRedirectedDirection(origin)
                    if redirectedDirection then
                        direction = redirectedDirection
                    end
                end
            end
            return oldFunc(self, origin, direction, params)
        end)
        
        _G.OriginalFunctions["MeleeRaycast_Function"] = oldFunc
        print("[Player Modifier - Killaura] Direct function raycast hook set up.")
    end
end

function Killaura:Init(Tab)
    _G.ModifierRuntime = _G.ModifierRuntime or {}

    -- Activate Raycast hooks
    setupRaycastHook()

    if _G.ModifierRuntime.KillauraThread and coroutine.status(_G.ModifierRuntime.KillauraThread) ~= "dead" then
        print("[Player Modifier - Killaura] Worker already running.")
        return
    end

    -- Start loop for auto-swinging Melee weapons
    local workerThread = task.spawn(function()
        print("[Player Modifier - Killaura] Melee auto-swing worker thread started.")
        while true do
            local delayTime = getModifierState("KillauraDelay", 0.2)
            if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                delayTime = _G.PerformanceGuard.GetDelay(delayTime, "heavy")
            end

            task.wait(delayTime)
            
            -- Break if manager global is cleared (Unloaded)
            if not _G.ModifierStates then
                print("[Player Modifier - Killaura] Worker terminated due to unload.")
                break
            end

            if _G.ModifierStates.Killaura then
                local target = getClosestMeleeTarget()
                if target then
                    local char = LocalPlayer.Character
                    local currentTool = findEquippedMelee(char)
                    
                    -- Check if tool is a melee weapon
                    if currentTool then
                        if not performSwing() then
                            debugLog("Swing failed for target=" .. tostring(target.Name))
                        end
                    else
                        debugLog("Target found but no equipped melee tool: " .. tostring(target.Name))
                    end
                else
                    debugLog("No target in range.")
                end
            end
        end
    end)

    _G.ModifierRuntime.KillauraThread = workerThread
    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, {
            Destroy = function()
                pendingSwingReleaseAt = 0
                releaseSwingInput()
            end,
        })
        table.insert(_G.ModifierConnections, workerThread)
    end
end

return Killaura
