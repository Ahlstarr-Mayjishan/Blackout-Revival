--[[
    ========================================================================
    Player Modifier - AntiFlashbang Module
    ========================================================================
    Bypasses and neutralizes client-side flashbang and concussion effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local AntiFlashbang = {}
AntiFlashbang.Name = "Anti-Flashbang Logic"
AntiFlashbang.Description = "Prevents client-side screen blinding and audio distortion from flashbangs."

function AntiFlashbang:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}

    -- 1. Hook the Flashbang RemoteEvent listener connect call
    local hookSuccess, err = pcall(function()
        if not hookfunction then return end
        if _G.OriginalFunctions["Flashbang_Connect"] then return end

        local flashbangRemote = ReplicatedStorage:WaitForChild("Events", 5) 
            and ReplicatedStorage.Events:WaitForChild("Player", 5) 
            and ReplicatedStorage.Events.Player:WaitForChild("Flashbang", 5)
            
        if flashbangRemote then
            local oldConnect
            oldConnect = hookfunction(flashbangRemote.OnClientEvent.Connect, function(self, fn)
                -- Wrap connection to intercept and discard the payload when enabled
                local wrapped = function(...)
                    if _G.ModifierStates and _G.ModifierStates.AntiFlashbang then
                        print("[Player Modifier - AntiFlashbang] Prevented client flashbang execution.")
                        return
                    end
                    return fn(...)
                end
                return oldConnect(self, wrapped)
            end)
            
            _G.OriginalFunctions["Flashbang_Connect"] = oldConnect
            print("[Player Modifier - AntiFlashbang] Hooked Flashbang.OnClientEvent.Connect successfully.")
        else
            warn("[Player Modifier - AntiFlashbang] Flashbang remote event not found.")
        end
    end)

    if not hookSuccess then
        warn("[Player Modifier - AntiFlashbang] Hooking connection failed: " .. tostring(err))
    end

    -- 2. State-level status effect attributes backup bypass loop
    local stateConnection = RunService.RenderStepped:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.AntiFlashbang then
            return
        end

        pcall(function()
            if _G.CharacterStates then
                -- Direct status effect protection attributes modification
                _G.CharacterStates.FlashProtection = 1
                _G.CharacterStates.ConcussionProtection = 1
            end
        end)
    end)

    table.insert(_G.ModifierConnections, stateConnection)
    print("[Player Modifier - AntiFlashbang] Initialized.")
end

return AntiFlashbang
