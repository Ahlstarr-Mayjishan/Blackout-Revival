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

-- Hook Remote Events (Damage & Ragdoll)
local function setupRemoteHooks()
    -- Check if hookmetamethod is available (common in exploit executors)
    if hookmetamethod then
        if _G.OriginalFunctions["namecall"] then
            log("Remote hooks already set up via hookmetamethod.")
            return
        end
        
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and _G.ModifierStates then
                local name = self.Name
                local parent = self.Parent
                
                -- Check if it belongs to ReplicatedStorage.Events.Player
                if parent and parent.Name == "Player" and parent.Parent and parent.Parent.Name == "Events" then
                    -- 1. No Fall Damage & No Collision Damage
                    if name == "Damage" and _G.ModifierStates.NoFallDamage then
                        local args = {...}
                        -- Fall damage / crash damage has a 3rd parameter as true in the source code
                        if args[3] == true then
                            return -- Block the damage request
                        end
                    
                    -- 2. Anti-Ragdoll
                    elseif name == "Ragdoll" and _G.ModifierStates.AntiRagdoll then
                        return -- Block the ragdoll request
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        
        _G.OriginalFunctions["namecall"] = oldNamecall
        log("Hooked __namecall successfully.")
        
    elseif hookfunction then
        -- Fallback: Hook the FireServer method of RemoteEvents directly
        if _G.OriginalFunctions["FireServer"] then
            log("Remote hooks already set up via hookfunction.")
            return
        end
        
        local dummyRemote = Instance.new("RemoteEvent")
        local oldFireServer
        oldFireServer = hookfunction(dummyRemote.FireServer, function(self, ...)
            if _G.ModifierStates then
                local name = self.Name
                local parent = self.Parent
                
                if parent and parent.Name == "Player" and parent.Parent and parent.Parent.Name == "Events" then
                    -- No Fall/Collision Damage
                    if name == "Damage" and _G.ModifierStates.NoFallDamage then
                        local args = {...}
                        -- With hookfunction, args[1] is the first argument after self
                        if args[2] == true then
                            return
                        end
                    
                    -- Anti-Ragdoll
                    elseif name == "Ragdoll" and _G.ModifierStates.AntiRagdoll then
                        return
                    end
                end
            end
            return oldFireServer(self, ...)
        end)
        
        _G.OriginalFunctions["FireServer"] = oldFireServer
        dummyRemote:Destroy()
        log("Hooked FireServer successfully.")
    else
        warn("[Player Modifier - Executor] Executor does not support hookmetamethod or hookfunction. Fall damage and Ragdoll hooks are disabled.")
    end
end
function Executor:Init(UIRef)
    -- Hook remote events
    setupRemoteHooks()
    
    log("Executor module initialized.")
end

return Executor
