--[[
    ========================================================================
    Player Modifier - InfiniteStamina Module
    ========================================================================
    Provides client-side and network-level stamina depletion bypasses.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local InfiniteStamina = {}
InfiniteStamina.Name = "Infinite Stamina Logic"
InfiniteStamina.Description = "Blocks stamina depletion remote events and overrides local stamina state."

-- Safely retrieve the PLAYER_STORAGE folder for the client
local function getPlayerStorage()
    local storageName = Players:GetAttribute("PLAYER_STORAGE")
    return storageName and LocalPlayer:FindFirstChild(storageName)
end

-- Safely retrieve the Stamina depletion remote
local function getStaminaRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    local playerEvents = events and events:FindFirstChild("Player")
    return playerEvents and playerEvents:FindFirstChild("Stamina")
end

function InfiniteStamina:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}

    -- 1. Hook namecalls used by the game for stamina reads/drain requests.
    local successNamecall, errNamecall = pcall(function()
        if not hookmetamethod then return end
        if _G.OriginalFunctions["InfiniteStamina_Namecall"] then return end

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if _G.ModifierStates and _G.ModifierStates.InfiniteStamina then
                local storage = getPlayerStorage()

                if method == "GetAttribute" and self == storage and args[1] == "Stamina" then
                    return 100
                end

                if method == "SetAttribute" and self == storage and args[1] == "Stamina" then
                    args[2] = 100
                    return oldNamecall(self, table.unpack(args))
                end

                if method == "FireServer" and self == getStaminaRemote() then
                    return nil
                end
            end

            return oldNamecall(self, ...)
        end)

        _G.OriginalFunctions["InfiniteStamina_Namecall"] = oldNamecall
        print("[Player Modifier - InfiniteStamina] Successfully hooked stamina namecalls.")
    end)

    if not successNamecall then
        warn("[Player Modifier - InfiniteStamina] Failed to hook stamina namecalls: " .. tostring(errNamecall))
    end

    -- 2. Fallback hook for executors that support direct method replacement better.
    local successRemote, errRemote = pcall(function()
        if not hookfunction then return end
        if _G.OriginalFunctions["Stamina_FireServer"] then return end

        local staminaRemote = getStaminaRemote()
        if staminaRemote then
            local originalFireServer
            originalFireServer = hookfunction(staminaRemote.FireServer, function(self, ...)
                if _G.ModifierStates and _G.ModifierStates.InfiniteStamina then
                    return nil -- Intercept and block outbound stamina drain
                end
                return originalFireServer(self, ...)
            end)
            
            _G.OriginalFunctions["Stamina_FireServer"] = originalFireServer
            print("[Player Modifier - InfiniteStamina] Successfully hooked Stamina.FireServer.")
        else
            warn("[Player Modifier - InfiniteStamina] Stamina remote event not found.")
        end
    end)

    if not successRemote then
        warn("[Player Modifier - InfiniteStamina] Failed to hook Stamina.FireServer: " .. tostring(errRemote))
    end

    -- 3. Local state overwrite loop
    local stateConnection = RunService.RenderStepped:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.InfiniteStamina then
            return
        end

        pcall(function()
            local storage = getPlayerStorage()
            if storage then
                storage:SetAttribute("Stamina", 100)
            end
            if _G.CharacterStates then
                _G.CharacterStates.Stamina = 100
            end
        end)
    end)

    table.insert(_G.ModifierConnections, stateConnection)
    print("[Player Modifier - InfiniteStamina] Initialized.")
end

return InfiniteStamina
