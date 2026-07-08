--[[
    ========================================================================
    Player Modifier - InfiniteStamina Module
    ========================================================================
    Provides client-side and network-level stamina depletion bypasses.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local InfiniteStamina = {}
InfiniteStamina.Name = "Infinite Stamina Logic"
InfiniteStamina.Description = "Blocks stamina depletion remote events and overrides local stamina state."

local STAMINA_VALUE = 100
local STAMINA_REFRESH_INTERVAL = 0.15
local cachedStorageName = nil
local cachedStorage = nil
local cachedStaminaRemote = nil

-- Safely retrieve the PLAYER_STORAGE folder for the client
local function getPlayerStorage()
    local storageName = Players:GetAttribute("PLAYER_STORAGE")
    if not storageName then
        return nil
    end

    if cachedStorage and cachedStorage.Parent == LocalPlayer and cachedStorageName == storageName then
        return cachedStorage
    end

    cachedStorageName = storageName
    cachedStorage = LocalPlayer:FindFirstChild(storageName)
    return cachedStorage
end

-- Safely retrieve the Stamina depletion remote
local function getStaminaRemote()
    if cachedStaminaRemote and cachedStaminaRemote.Parent then
        return cachedStaminaRemote
    end

    local events = ReplicatedStorage:FindFirstChild("Events")
    local playerEvents = events and events:FindFirstChild("Player")
    cachedStaminaRemote = playerEvents and playerEvents:FindFirstChild("Stamina")
    return cachedStaminaRemote
end

local function forceStamina()
    local storage = getPlayerStorage()
    if storage and storage:GetAttribute("Stamina") ~= STAMINA_VALUE then
        storage:SetAttribute("Stamina", STAMINA_VALUE)
    end

    if _G.CharacterStates then
        _G.CharacterStates.Stamina = STAMINA_VALUE
    end
end

local function ensureStorageWatcher()
    if _G.ModifierRuntime and _G.ModifierRuntime.InfiniteStaminaAttributeConnection then
        return
    end

    local storage = getPlayerStorage()
    if not storage then
        return
    end

    local attributeConnection = storage:GetAttributeChangedSignal("Stamina"):Connect(function()
        if _G.ModifierStates and _G.ModifierStates.InfiniteStamina then
            pcall(forceStamina)
        end
    end)

    _G.ModifierRuntime.InfiniteStaminaAttributeConnection = attributeConnection
    table.insert(_G.ModifierConnections, attributeConnection)
end

function InfiniteStamina:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}
    _G.ModifierRuntime = _G.ModifierRuntime or {}

    -- Older builds installed a global __namecall hook here. It touched every
    -- game namecall and could freeze the client, so restore it if it exists.
    if _G.OriginalFunctions["InfiniteStamina_Namecall"] and hookmetamethod then
        pcall(function()
            hookmetamethod(game, "__namecall", _G.OriginalFunctions["InfiniteStamina_Namecall"])
        end)
        _G.OriginalFunctions["InfiniteStamina_Namecall"] = nil
        print("[Player Modifier - InfiniteStamina] Removed heavy stamina namecall hook.")
    end

    -- 1. Hook only the stamina drain remote instead of all namecalls.
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

    -- 2. React only when the stamina attribute changes.
    ensureStorageWatcher()

    -- 3. Lightweight safety loop in case the storage object appears later or a
    -- drain happens without AttributeChanged firing.
    if not _G.ModifierRuntime.InfiniteStaminaThread then
        local loopThread = task.spawn(function()
            while _G.ModifierStates do
                if _G.ModifierStates.InfiniteStamina then
                    ensureStorageWatcher()
                    pcall(forceStamina)
                end

                task.wait(STAMINA_REFRESH_INTERVAL)
            end
        end)

        _G.ModifierRuntime.InfiniteStaminaThread = loopThread
        table.insert(_G.ModifierConnections, loopThread)
    end

    print("[Player Modifier - InfiniteStamina] Initialized.")
end

return InfiniteStamina
