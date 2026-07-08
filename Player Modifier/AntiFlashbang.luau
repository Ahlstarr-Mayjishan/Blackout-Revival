--[[
    ========================================================================
    Player Modifier - AntiFlashbang Module
    ========================================================================
    Bypasses and neutralizes client-side flashbang and concussion effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer

local AntiFlashbang = {}
AntiFlashbang.Name = "Anti-Flashbang Logic"
AntiFlashbang.Description = "Prevents client-side screen blinding and audio distortion from flashbangs."

local CLEANUP_INTERVAL = 0.08
local CACHE_REFRESH_INTERVAL = 1
local GLARE_CLEANUP_INTERVAL = 0.25

local cachedEffects = {}
local lastCacheRefresh = 0
local lastGlareCleanup = 0

local function getFlashbangGui()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil
    end

    return playerGui:FindFirstChild("Flashbang")
end

local function refreshEffectCache(force)
    local now = os.clock()
    if not force and now - lastCacheRefresh < CACHE_REFRESH_INTERVAL then
        return
    end

    lastCacheRefresh = now
    cachedEffects.FlashCC = Lighting:FindFirstChild("FlashCC")
    cachedEffects.FlashBlur = Lighting:FindFirstChild("FlashBlur")
    cachedEffects.ConcussionCC = Lighting:FindFirstChild("ConcussionCC")
    cachedEffects.ConcussionBlur = Lighting:FindFirstChild("ConcussionBlur")

    local generalSoundGroup = SoundService:FindFirstChild("GeneralSoundGroup")
    cachedEffects.Eq = generalSoundGroup and generalSoundGroup:FindFirstChild("Eq")
    cachedEffects.ConcussionEq = generalSoundGroup and generalSoundGroup:FindFirstChild("ConcussionEq")

    local flashbangGui = getFlashbangGui()
    cachedEffects.FlashbangGui = flashbangGui
    cachedEffects.Flash = flashbangGui and flashbangGui:FindFirstChild("Flash")
    cachedEffects.Blind = flashbangGui and flashbangGui:FindFirstChild("Blind")
end

local function setEffect(instance, properties)
    if not instance then
        return
    end

    for property, value in pairs(properties) do
        pcall(function()
            instance[property] = value
        end)
    end
end

local function neutralizeFlashEffects()
    refreshEffectCache(false)

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if root then
        pcall(function()
            root:SetAttribute("AntiFlash", true)
        end)
    end

    if _G.CharacterStates then
        _G.CharacterStates.FlashProtection = 1
        _G.CharacterStates.ConcussionProtection = 1
    end

    setEffect(cachedEffects.FlashCC, {
        Contrast = 0,
        Saturation = 0,
        TintColor = Color3.new(1, 1, 1),
    })

    setEffect(cachedEffects.FlashBlur, {
        Size = 0,
        Enabled = false,
    })

    setEffect(cachedEffects.ConcussionCC, {
        Contrast = 0,
        Saturation = 0,
        TintColor = Color3.new(1, 1, 1),
    })

    setEffect(cachedEffects.ConcussionBlur, {
        Size = 0,
        Enabled = false,
    })

    setEffect(cachedEffects.Eq, {
        Enabled = false,
        HighGain = 0,
        MidGain = 0,
        LowGain = 0,
    })

    setEffect(cachedEffects.ConcussionEq, {
        Enabled = false,
        HighGain = 0,
        MidGain = 0,
        LowGain = 0,
    })

    setEffect(cachedEffects.Flash, {
        BackgroundTransparency = 1,
    })

    setEffect(cachedEffects.Blind, {
        BackgroundTransparency = 1,
    })

    local now = os.clock()
    local flashbangGui = cachedEffects.FlashbangGui
    if flashbangGui and now - lastGlareCleanup >= GLARE_CLEANUP_INTERVAL then
        lastGlareCleanup = now
        for _, child in ipairs(flashbangGui:GetChildren()) do
            if child.Name == "Glare" then
                child:Destroy()
            end
        end
    end
end

function AntiFlashbang:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}
    _G.ModifierRuntime = _G.ModifierRuntime or {}

    -- 1. Hook root AntiFlash reads. The game checks HumanoidRootPart:GetAttribute("AntiFlash").
    local namecallSuccess, namecallErr = pcall(function()
        if not hookmetamethod then return end
        if _G.OriginalFunctions["AntiFlashbang_Namecall"] then return end

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if _G.ModifierStates and _G.ModifierStates.AntiFlashbang then
                if method == "GetAttribute" and args[1] == "AntiFlash" then
                    local character = LocalPlayer.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    if self == root then
                        return true
                    end
                end
            end

            return oldNamecall(self, ...)
        end)

        _G.OriginalFunctions["AntiFlashbang_Namecall"] = oldNamecall
        print("[Player Modifier - AntiFlashbang] Hooked AntiFlash attribute reads.")
    end)

    if not namecallSuccess then
        warn("[Player Modifier - AntiFlashbang] AntiFlash namecall hook failed: " .. tostring(namecallErr))
    end

    -- 2. Hook future Flashbang RemoteEvent listener connect calls. This is a fallback because
    -- FlashbangCore may already be connected before this module loads.
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

    refreshEffectCache(true)

    -- 3. State-level status effect and visual/audio cleanup loop.
    -- This used to run every RenderStepped; a timed loop is much lighter and
    -- still clears flash/concussion effects before they become visible for long.
    if not _G.ModifierRuntime.AntiFlashbangCleanupThread then
        local cleanupThread = task.spawn(function()
            while _G.ModifierStates do
                if _G.ModifierStates.AntiFlashbang then
                    pcall(neutralizeFlashEffects)
                end

                task.wait(CLEANUP_INTERVAL)
            end
        end)

        _G.ModifierRuntime.AntiFlashbangCleanupThread = cleanupThread
        table.insert(_G.ModifierConnections, cleanupThread)
    end

    print("[Player Modifier - AntiFlashbang] Initialized.")
end

return AntiFlashbang
