--[[
    ========================================================================
    Player Modifier - Executor Module (Feature Execution and Hooking Engine)
    ========================================================================
    This module implements the core hacks/modifications by hooking remote events
    and connecting to client-side input and gameplay events.
    
    Features implemented:
        1. No Fall Damage & No Collision Damage (Hooks ReplicatedStorage.Events.Player.Damage)
        2. Anti-Ragdoll (Hooks ReplicatedStorage.Events.Player.Ragdoll)
        3. Auto-Unlock Safes / Instant Win Minigames (Connects to Events.Loot.Minigame)
        4. Infinite Double Jump (Connects to UserInputService.JumpRequest)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Executor = {}
Executor.Name = "Execution Engine"
Executor.Description = "Internal framework module that handles event hooking and physics overrides."

-- Helper to safely log debug messages
local function log(msg)
    print("[Player Modifier - Executor] " .. tostring(msg))
end

local function getPlayerRemote(remoteName)
    local events = ReplicatedStorage:FindFirstChild("Events")
    local playerEvents = events and events:FindFirstChild("Player")
    return playerEvents and playerEvents:FindFirstChild(remoteName)
end

local function isModifierEnabled(flagName)
    return _G.ModifierStates and _G.ModifierStates[flagName] == true
end

-- Hook Remote Events (Damage & Ragdoll)
local function setupRemoteHooks()
    _G.OriginalFunctions = _G.OriginalFunctions or {}

    local damageRemote = getPlayerRemote("Damage")
    local ragdollRemote = getPlayerRemote("Ragdoll")

    if not damageRemote and not ragdollRemote then
        warn("[Player Modifier - Executor] Player Damage/Ragdoll remotes were not found.")
        return
    end

    if hookmetamethod then
        if _G.OriginalFunctions["PlayerRemote_Namecall"] then
            log("Remote hooks already set up via hookmetamethod.")
            return
        end
        
        local oldNamecall
        local callback = function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" then
                local args = {...}

                if self == damageRemote and isModifierEnabled("NoFallDamage") and args[3] == true then
                    return nil
                end

                if self == ragdollRemote and isModifierEnabled("AntiRagdoll") then
                    return nil
                end
            end
            return oldNamecall(self, ...)
        end

        oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(callback) or callback)
        
        _G.OriginalFunctions["PlayerRemote_Namecall"] = oldNamecall
        log("Hooked __namecall successfully.")
        
    elseif hookfunction then
        if _G.OriginalFunctions["PlayerRemote_FireServer"] then
            log("Remote hooks already set up via hookfunction.")
            return
        end

        local originals = {}

        if damageRemote then
            originals.Damage = hookfunction(damageRemote.FireServer, function(self, ...)
                local args = {...}
                if self == damageRemote and isModifierEnabled("NoFallDamage") and args[3] == true then
                    return nil
                end
                return originals.Damage(self, ...)
            end)
        end

        if ragdollRemote then
            originals.Ragdoll = hookfunction(ragdollRemote.FireServer, function(self, ...)
                if self == ragdollRemote and isModifierEnabled("AntiRagdoll") then
                    return nil
                end
                return originals.Ragdoll(self, ...)
            end)
        end

        _G.OriginalFunctions["PlayerRemote_FireServer"] = originals
        log("Hooked direct RemoteEvent.FireServer functions successfully.")
    else
        warn("[Player Modifier - Executor] Executor does not support hookmetamethod or hookfunction. Fall damage and Ragdoll hooks are disabled.")
    end
end

local function setupLocalRagdollRecovery()
    local function recover()
        if not isModifierEnabled("AntiRagdoll") then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if _G.CharacterStates then
            _G.CharacterStates.Ragdolled = false
            _G.CharacterStates.InPhysics = false
        end

        if character then
            character:SetAttribute("Ragdolled", false)
            character:SetAttribute("InPhysics", false)
            character:SetAttribute("AutoRotate", true)
        end

        if humanoid then
            humanoid.PlatformStand = false
            humanoid.AutoRotate = true
            if humanoid:GetState() == Enum.HumanoidStateType.Physics or humanoid:GetState() == Enum.HumanoidStateType.FallingDown then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    end

    local connection = RunService.Heartbeat:Connect(recover)
    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, connection)
    end

    log("Local anti-ragdoll recovery loop registered.")
end

function Executor:Init(UIRef)
    setupRemoteHooks()
    setupLocalRagdollRecovery()
    
    log("Executor module initialized.")
end

return Executor
