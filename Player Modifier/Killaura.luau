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

local Killaura = {}
Killaura.Name = "Killaura (Melee) Logic"
Killaura.Description = "Automates melee swings and redirects blade collision points directly to targets."

-- Scan for closest valid target inside melee range (15 studs)
local function getClosestMeleeTarget()
    local localChar = LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
        return nil
    end

    local localPos = localChar.HumanoidRootPart.Position
    local closestTarget = nil
    local closestDist = _G.ModifierStates and _G.ModifierStates.KillauraRange or 30

    local folders = {}
    local chars = Workspace:FindFirstChild("Chars")
    if chars then table.insert(folders, chars) end
    local npcs = Workspace:FindFirstChild("NPCs")
    if npcs then table.insert(folders, npcs) end
    if #folders == 0 then table.insert(folders, Workspace) end

    for _, folder in ipairs(folders) do
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and child ~= localChar and child:FindFirstChild("Humanoid") and child:FindFirstChild("HumanoidRootPart") then
                -- Check if alive
                local hum = child.Humanoid
                if hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
                    -- Team filter check
                    local isAlly = false
                    local player = Players:GetPlayerFromCharacter(child)
                    if player and player.Team == LocalPlayer.Team and LocalPlayer.Team ~= nil then
                        isAlly = true
                    end

                    if not isAlly then
                        local root = child.HumanoidRootPart
                        local dist = (root.Position - localPos).Magnitude
                        if dist < closestDist then
                            closestTarget = child
                            closestDist = dist
                        end
                    end
                end
            end
        end
    end

    return closestTarget
end

-- Establish Raycast redirection hook for Blatant Mode
local function setupRaycastHook()
    if hookmetamethod then
        if _G.OriginalFunctions["MeleeRaycast_Metatable"] then return end
        
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "Raycast" and _G.ModifierStates and _G.ModifierStates.Killaura and _G.ModifierStates.KillauraMode == "Blatant" and _G.ModifierStates.KillauraHitAt ~= "off" then
                local args = {...}
                local origin = args[1]
                local direction = args[2]
                local params = args[3]
                
                -- Verify it is Melee Hitbox raycast (excludes gun RayCasts collision group)
                if params and params.FilterDescendantsInstances and params.CollisionGroup ~= "RayCasts" then
                    local target = getClosestMeleeTarget()
                    if target then
                        local targetPartName = _G.ModifierStates.KillauraHitAt == "head" and "Head" or "Torso"
                        local targetPart = target:FindFirstChild(targetPartName) or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("UpperTorso")
                        if targetPart then
                            -- Redirect melee ray straight to target part
                            args[2] = (targetPart.Position - origin)
                            return oldNamecall(self, unpack(args))
                        end
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
                if params and params.FilterDescendantsInstances and params.CollisionGroup ~= "RayCasts" then
                    local target = getClosestMeleeTarget()
                    if target then
                        local targetPartName = _G.ModifierStates.KillauraHitAt == "head" and "Head" or "Torso"
                        local targetPart = target:FindFirstChild(targetPartName) or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("UpperTorso")
                        if targetPart then
                            direction = (targetPart.Position - origin)
                        end
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
    -- Activate Raycast hooks
    setupRaycastHook()

    -- Start loop for auto-swinging Melee weapons
    task.spawn(function()
        print("[Player Modifier - Killaura] Melee auto-swing worker thread started.")
        while true do
            local delayTime = _G.ModifierStates and _G.ModifierStates.KillauraDelay or 0.2
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
                    local currentTool = char and char:FindFirstChildOfClass("Tool")
                    
                    -- Check if tool is a melee weapon
                    if currentTool and currentTool:FindFirstChild("MeleeStatus") then
                        local meleeMain = nil
                        pcall(function()
                            local mods = ReplicatedStorage:FindFirstChild("MeleeStorage") and ReplicatedStorage.MeleeStorage:FindFirstChild("Mods")
                            if mods and mods:FindFirstChild("Main") then
                                meleeMain = require(mods.Main)
                            end
                        end)

                        if meleeMain then
                            -- Auto-vung weapon
                            pcall(function()
                                meleeMain.Swing(true)
                                task.wait(0.05)
                                meleeMain.Swing(false)
                            end)
                        end
                    end
                end
            end
        end
    end)
end

return Killaura
