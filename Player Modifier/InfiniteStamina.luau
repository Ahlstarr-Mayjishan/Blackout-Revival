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
    return storageName and Players:FindFirstChild(storageName)
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

    -- 1. Hook the GetAttribute function to return 100 for "Stamina"
    local successGetAttr, errGetAttr = pcall(function()
        if not hookfunction then return end
        if _G.OriginalFunctions["GetAttribute"] then return end

        local dummyInstance = Instance.new("Folder")
        local originalGetAttribute
        originalGetAttribute = hookfunction(dummyInstance.GetAttribute, function(self, attribute, ...)
            if _G.ModifierStates and _G.ModifierStates.InfiniteStamina and attribute == "Stamina" then
                local storage = getPlayerStorage()
                if storage and self == storage then
                    return 100
                end
            end
            return originalGetAttribute(self, attribute, ...)
        end)

        _G.OriginalFunctions["GetAttribute"] = originalGetAttribute
        dummyInstance:Destroy()
        print("[Player Modifier - InfiniteStamina] Successfully hooked GetAttribute.")
    end)

    if not successGetAttr then
        warn("[Player Modifier - InfiniteStamina] Failed to hook GetAttribute: " .. tostring(errGetAttr))
    end

    -- 2. Hook Stamina remote FireServer call to prevent stamina drain requests
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
