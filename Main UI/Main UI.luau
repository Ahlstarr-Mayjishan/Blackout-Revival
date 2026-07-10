--[[
    ========================================================================
    Player Modifier - Main UI (Module Loading System)
    ========================================================================
    Developed for: Player Modifier Suite
    UI Library: Rayfield UI Library (Sirius)
    
    This script initializes Rayfield UI, sets up stable feature tabs,
    and dynamically loads client modules from local files or GitHub raw URLs.
    
    How to create modules:
    Place a file (e.g., 'SpeedFly.luau') inside the 'Player Modifier' folder.
    The file must return a table containing:
        - Name (string)
        - Description (string)
        - Init (function) -> Called when the module loads, receives the Tab object.
    
    Example Module:
    ------------------------------------------------------------------------
    local Module = {}
    Module.Name = "Speed Hack"
    Module.Description = "Modifies player's walkspeed."
    
    function Module:Init(Tab)
        Tab:CreateSlider({
            Name = "WalkSpeed",
            Range = {16, 500},
            Increment = 1,
            CurrentValue = 16,
            Callback = function(Value)
                game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = Value
            end,
        })
    end
    
    return Module
    ------------------------------------------------------------------------
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local repairServerGunModel = nil
local lastWeaponRepairLog = 0

local DEFAULT_CHARACTER_STATES = {
    Aiming = false,
    Blocking = false,
    ServerBlocking = false,
    UsingItem = false,
    Reloading = false,
    GunPreparing = false,
    PreparingSwing = false,
    Swinging = false,
    Finishing = false,
    Sprinting = false,
    Sliding = false,
    Downed = false,
    Ragdolled = false,
    InPhysics = false,
    AimingMovementSpeed = nil,
    ReloadingMovementSpeed = nil,
}

local function restoreAimWeaponHooks()
    local originals = _G.AimAssistOriginals
    if type(originals) ~= "table" then
        return
    end

    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Mods")
        local fastCastModule = mods and mods:FindFirstChild("FastCast")
        if fastCastModule then
            local fastCastTable = require(fastCastModule)
            local originalFastCast = originals["FastCast_Fire"] or originals["HomingBullets_FastCast_Fire"]
            if originalFastCast and type(fastCastTable) == "table" then
                fastCastTable.Fire = originalFastCast
            end
        end
    end)

    pcall(function()
        local gunStorage = ReplicatedStorage:FindFirstChild("GunStorage")
        local bulletHandlerModule = gunStorage
            and gunStorage:FindFirstChild("Mods")
            and gunStorage.Mods:FindFirstChild("BulletHandler")

        if bulletHandlerModule then
            local bulletHandler = require(bulletHandlerModule)
            local originalBulletHandler = originals["BulletHandler_Fire"] or originals["HomingBullets_BulletHandler_Fire"]
            if originalBulletHandler and type(bulletHandler) == "table" then
                bulletHandler.Fire = originalBulletHandler
            end
        end
    end)

    originals["FastCast_Fire"] = nil
    originals["HomingBullets_FastCast_Fire"] = nil
    originals["BulletHandler_Fire"] = nil
    originals["HomingBullets_BulletHandler_Fire"] = nil
end

local function clearStuckWeaponStates()
    if type(_G.AimAssistStates) == "table" then
        _G.AimAssistStates.Enabled = false
        _G.AimAssistStates.RecoilControlActive = false
        _G.AimAssistStates.SilentAimActive = false
        _G.AimAssistStates.HomingBulletsActive = false
    end

    restoreAimWeaponHooks()

    local recoilOriginals = _G.AimAssistOriginals and _G.AimAssistOriginals.RecoilControlStats
    if type(recoilOriginals) == "table" then
        for container, values in pairs(recoilOriginals) do
            if typeof(container) == "Instance" and container.Parent then
                for key, value in pairs(values) do
                    pcall(function()
                        container:SetAttribute(key, value)
                    end)
                end
            elseif type(container) == "table" then
                for key, value in pairs(values) do
                    pcall(function()
                        container[key] = value
                    end)
                end
            end
        end

        _G.AimAssistOriginals.RecoilControlStats = nil
    end

    local states = rawget(_G, "CharacterStates") or _G.CharacterStates

    if type(states) == "table" then
        for _, key in ipairs({
            "Blocking",
            "ServerBlocking",
            "UsingItem",
            "Reloading",
            "GunPreparing",
            "PreparingSwing",
            "Swinging",
            "Finishing",
        }) do
            pcall(function()
                states[key] = false
            end)
        end

        for _, key in ipairs({
            "DisableInventory",
            "ForceEquip",
            "E",
            "NT",
            "Endlag",
            "RestrictedMovement",
        }) do
            pcall(function()
                states[key] = nil
            end)
        end
    end

    local character = Players.LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        pcall(function()
            local state = humanoid:GetState()
            if state == Enum.HumanoidStateType.Physics
                or state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.PlatformStanding then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end

    if repairServerGunModel then
        pcall(repairServerGunModel)
    end

    pcall(function()
        local si = ReplicatedStorage:FindFirstChild("SI")
        if si and type(si.Fire) == "function" then
            si:Fire(true)
        end
    end)

    print("[Blackout UI] Cleared stuck weapon/inventory states.")
end

_G.FixBlackoutWeapon = clearStuckWeaponStates

local function disconnectItems(items)
    if type(items) ~= "table" then
        return
    end

    for _, item in ipairs(items) do
        pcall(function()
            if typeof(item) == "RBXScriptConnection" then
                if item.Connected then
                    item:Disconnect()
                end
            elseif typeof(item) == "thread" then
                task.cancel(item)
            elseif type(item) == "table" and type(item.Remove) == "function" then
                item:Remove()
            elseif type(item) == "table" and type(item.Destroy) == "function" then
                item:Destroy()
            end
        end)
    end

    table.clear(items)
end

local function ensureCharacterStatesFallback()
    if type(rawget(_G, "CharacterStates")) == "table" or type(_G.CharacterStates) == "table" then
        return false
    end

    local character = Players.LocalPlayer.Character
    local states = {}

    if character then
        local ok, attributes = pcall(function()
            return character:GetAttributes()
        end)

        if ok and type(attributes) == "table" then
            for key, value in pairs(attributes) do
                states[key] = value
            end
        end
    end

    for key, value in pairs(DEFAULT_CHARACTER_STATES) do
        if states[key] == nil then
            states[key] = value
        end
    end

    rawset(_G, "CharacterStates", states)
    print("[Blackout UI] Restored fallback _G.CharacterStates snapshot.")
    return true
end

local function getEquippedGunSettings(character)
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:GetAttribute("Tool") and child:FindFirstChild("GunStatus") then
            local settingsModule = child:FindFirstChild("Settings")
            if settingsModule then
                local ok, settings = pcall(require, settingsModule)
                if ok and type(settings) == "table" then
                    return settings
                end
            end
        end
    end

    return nil
end

local function ensureValueChild(parent, name, value)
    local child = parent:FindFirstChild(name)
    local valueType = type(value)

    if not child then
        if valueType == "boolean" then
            child = Instance.new("BoolValue")
        elseif valueType == "number" then
            child = Instance.new("NumberValue")
        elseif valueType == "string" then
            child = Instance.new("StringValue")
        else
            child = Instance.new("Folder")
        end

        child.Name = name
        child.Parent = parent
    end

    pcall(function()
        if valueType == "boolean" or valueType == "number" or valueType == "string" then
            child.Value = value
        end
    end)

    return child
end

local function ensureTableFolder(parent, name, values)
    local folder = parent:FindFirstChild(name)
    local repaired = false

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = parent
        repaired = true
    end

    if type(values) == "table" then
        for key, value in pairs(values) do
            if folder:FindFirstChild(key) == nil then
                repaired = true
            end
            ensureValueChild(folder, key, value)
        end
    end

    return folder, repaired
end

repairServerGunModel = function()
    local character = Players.LocalPlayer.Character
    if not character then
        return false, "no character"
    end

    local serverGunModel = character:FindFirstChild("ServerGunModel")
    if not serverGunModel then
        return false, "no ServerGunModel"
    end

    local repaired = false
    local settingsTable = getEquippedGunSettings(character)

    if not serverGunModel:FindFirstChild("ShowCrosshair") then
        local showCrosshair = Instance.new("BoolValue")
        showCrosshair.Name = "ShowCrosshair"
        showCrosshair.Value = type(settingsTable) == "table" and settingsTable.ShowCrosshair ~= nil
            and settingsTable.ShowCrosshair
            or true
        showCrosshair.Parent = serverGunModel
        repaired = true
    end

    local _, repairedUnchambered = ensureTableFolder(
        serverGunModel,
        "Unchambered",
        type(settingsTable) == "table" and settingsTable.Unchambered or {
            InvisibleMagazine = false,
            PlayOnEquip = false,
        }
    )
    repaired = repaired or repairedUnchambered

    if not serverGunModel:FindFirstChild("Settings") then
        for _, child in ipairs(character:GetChildren()) do
            if child:GetAttribute("Tool") and child:FindFirstChild("GunStatus") then
                local settings = child:FindFirstChild("Settings")
                if settings then
                    local clonedSettings = settings:Clone()
                    clonedSettings.Parent = serverGunModel
                    repaired = true
                    break
                end
            end
        end
    end

    if repaired and os.clock() - lastWeaponRepairLog > 1 then
        lastWeaponRepairLog = os.clock()
        print("[Blackout UI] Repaired missing ServerGunModel client fields.")
    end

    return repaired, "ok"
end

_G.RepairBlackoutWeaponRuntime = repairServerGunModel

local function installWeaponRuntimeRepair()
    disconnectItems(_G.BlackoutUIConnections)
    _G.BlackoutUIConnections = {}

    local function watchCharacter(character)
        if not character then
            return
        end

        pcall(repairServerGunModel)

        table.insert(_G.BlackoutUIConnections, character.ChildAdded:Connect(function(child)
            if child.Name == "ServerGunModel" or child:GetAttribute("Tool") then
                task.defer(function()
                    pcall(repairServerGunModel)
                end)
            end
        end))
    end

    table.insert(_G.BlackoutUIConnections, Players.LocalPlayer.CharacterAdded:Connect(function(character)
        task.defer(function()
            watchCharacter(character)
        end)
    end))

    watchCharacter(Players.LocalPlayer.Character)

    local heartbeatConnection = RunService.Heartbeat:Connect(function()
        ensureCharacterStatesFallback()
        pcall(repairServerGunModel)
    end)

    table.insert(_G.BlackoutUIConnections, heartbeatConnection)
end

local function loadLocalGc(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return nil
    end

    local candidates = {
        path,
        "BlackoutRevival/" .. path,
        "BlackoutRevival\\" .. path:gsub("/", "\\"),
        "D:/Scripting/blackout revival/" .. path,
        "D:\\Scripting\\blackout revival\\" .. path:gsub("/", "\\"),
    }

    local sourcePath = nil
    for _, candidate in ipairs(candidates) do
        if isfile(candidate) then
            sourcePath = candidate
            break
        end
    end

    if not sourcePath then
        return nil
    end

    local ok, result = pcall(function()
        return loadstring(readfile(sourcePath))()
    end)

    if ok and type(result) == "table" and type(result.cleanup) == "function" then
        return result
    end

    return nil
end

local function destroyRayfieldGui()
    local candidates = {}

    pcall(function()
        if type(gethui) == "function" then
            table.insert(candidates, gethui())
        end
    end)

    pcall(function()
        table.insert(candidates, game:GetService("CoreGui"))
    end)

    pcall(function()
        local coreGui = game:GetService("CoreGui")
        if coreGui:FindFirstChild("RobloxGui") then
            table.insert(candidates, coreGui.RobloxGui)
        end
    end)

    pcall(function()
        local playerGui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            table.insert(candidates, playerGui)
        end
    end)

    for _, parent in ipairs(candidates) do
        local rayfieldGui = parent and parent:FindFirstChild("Rayfield")
        if rayfieldGui then
            rayfieldGui:Destroy()
        end
    end
end

local function stopBlackoutUI()
    print("[Blackout UI] Emergency cleanup started.")

    pcall(function()
        if _G.ModifierStates then
            for key in pairs(_G.ModifierStates) do
                _G.ModifierStates[key] = false
            end
        end

        if _G.AimAssistStates then
            for key in pairs(_G.AimAssistStates) do
                _G.AimAssistStates[key] = false
            end
        end

        _G.AutoParryActive = false
        _G.AttackProbeActive = false
        _G.AttackTargetProbeActive = false
        clearStuckWeaponStates()

        if _G.PerformanceGuard and type(_G.PerformanceGuard.Cleanup) == "function" then
            _G.PerformanceGuard.Cleanup()
        end
    end)

    local playerGc = loadLocalGc("Player Modifier/GC.luau")
    if playerGc then
        pcall(playerGc.cleanup)
    else
        disconnectItems(_G.ModifierConnections)
        _G.ModifierStates = nil
        _G.ModifierConnections = nil
        _G.ModifierRuntime = nil
        _G.OriginalFunctions = nil
        _G.PerformanceGuard = nil
        _G.PerformanceGuardState = nil
    end

    local aimGc = loadLocalGc("Aim Assits/GC.luau")
    if aimGc then
        pcall(aimGc.cleanup)
    else
        disconnectItems(_G.AimAssistConnections)
        _G.AimAssistStates = nil
        _G.AimAssistConnections = nil
        _G.AimAssistOriginals = nil
        _G.GetClosestAimTarget = nil
    end

    local lootsGc = loadLocalGc("Loots/GC.luau")
    if lootsGc then
        pcall(lootsGc.cleanup)
    else
        disconnectItems(_G.LootConnections)
        _G.LootStates = nil
        _G.LootConnections = nil
        _G.LootRuntime = nil
    end

    disconnectItems(_G.BlackoutUIConnections)
    _G.BlackoutUIConnections = nil

    pcall(function()
        if type(_G.StopAutoParry) == "function" then
            _G.StopAutoParry()
        end
        if type(_G.StopAttackProbe) == "function" then
            _G.StopAttackProbe()
        end
        if type(_G.StopAttackTargetProbe) == "function" then
            _G.StopAttackTargetProbe()
        end
    end)

    destroyRayfieldGui()
    print("[Blackout UI] Emergency cleanup finished.")
end

_G.StopBlackoutUI = stopBlackoutUI
_G.StopPlayerModifierUI = stopBlackoutUI
_G.UnloadBlackoutUI = stopBlackoutUI

-- 1. Load Rayfield UI Library
local Rayfield = nil
local success, loadedRayfieldOrErr = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if success and loadedRayfieldOrErr then
    Rayfield = loadedRayfieldOrErr
    print("Main UI | Rayfield UI successfully loaded.")
else
    warn("Main UI | Failed to fetch Rayfield from remote URL, using local mockup/fallback: " .. tostring(loadedRayfieldOrErr))
    -- Fallback/Mockup in case Rayfield cannot be loaded (for Studio testing)
    Rayfield = {
        Notify = function(_, cfg)
            print("Main UI (Mockup) | Notification: " .. tostring(cfg.Content))
        end,
        CreateWindow = function(_, cfg)
            print("Main UI (Mockup) | Window created: " .. tostring(cfg.Name))
            local WindowMock = {}
            WindowMock.CreateTab = function(_, name)
                print("Main UI (Mockup) | Tab created: " .. tostring(name))
                local TabMock = {}
                -- Mock tab methods
                local methods = {"CreateButton", "CreateToggle", "CreateSlider", "CreateDropdown", "CreateInput", "CreateKeybind", "CreateColorPicker", "CreateLabel", "CreateParagraph", "CreateSection"}
                for _, method in ipairs(methods) do
                    TabMock[method] = function(_, val)
                        print("Main UI (Mockup) | UI Element added [" .. method .. "]:", HttpService:JSONEncode(val))
                        return { Set = function() end, Refresh = function() end }
                    end
                end
                return TabMock
            end
            return WindowMock
        end
    }
end

-- 2. Create Rayfield Window
local Window = Rayfield:CreateWindow({
    Name = "Player Modifier",
    LoadingTitle = "Player Modifier Suite",
    LoadingSubtitle = "by Antigravity",
    Theme = "Default",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "PlayerModifier",
        FileName = "Config"
    },
    KeySystem = false
})

-- 3. Create stable Rayfield tabs. Do not manipulate Rayfield's internal frames;
-- those internals can change between library versions and break element parenting.
local Tabs = {
    Status = Window:CreateTab("Status", 4483362458),
    Player = Window:CreateTab("Player", 4483362458),
    Aim = Window:CreateTab("Aim Assist", 4483362458),
    AimModes = Window:CreateTab("Aim Modes", 4483362458),
    Loots = Window:CreateTab("Loots", 4483362458),
    System = Window:CreateTab("System", 4483362458),
}

local Tab = Tabs.Status

local function createSystemFallbackControls()
    local ok, err = pcall(function()
        Tabs.System:CreateSection("Emergency Controls")
        Tabs.System:CreateButton({
            Name = "Stop / Unload Everything",
            Callback = function()
                stopBlackoutUI()
            end,
        })
        Tabs.System:CreateButton({
            Name = "Fix Stuck Weapon / Inventory",
            Callback = function()
                clearStuckWeaponStates()
            end,
        })
        Tabs.System:CreateButton({
            Name = "Repair Weapon Runtime",
            Callback = function()
                repairServerGunModel()
            end,
        })
        Tabs.System:CreateLabel("Console: _G.StopBlackoutUI()")
        Tabs.System:CreateLabel("Console: _G.FixBlackoutWeapon()")
        Tabs.System:CreateLabel("Console: _G.RepairBlackoutWeaponRuntime()")
    end)

    if not ok then
        warn("Main UI | Failed to create fallback System controls: " .. tostring(err))
    end
end

createSystemFallbackControls()

local function sendNotification(cfg)
    if type(Rayfield) == "table" and type(Rayfield.Notify) == "function" then
        local ok = pcall(Rayfield.Notify, Rayfield, cfg)
        if ok then
            return
        end

        ok = pcall(Rayfield.Notify, cfg)
        if ok then
            return
        end
    end

    if type(Window) == "table" and type(Window.Notify) == "function" then
        pcall(Window.Notify, Window, cfg)
    end
end

local function normalizePath(path)
    return tostring(path):gsub("\\", "/")
end

local LOCAL_MODULE_ROOTS = {
    "BlackoutRevival/",
    "BlackoutRevival\\",
    "",
    "D:/Scripting/blackout revival/",
    "D:\\Scripting\\blackout revival\\",
}

local function getFileName(path)
    return normalizePath(path):match("[^/]+$") or tostring(path)
end

local function readModuleFile(folderPath, filePath)
    local normalizedFilePath = normalizePath(filePath)
    local backslashFilePath = normalizedFilePath:gsub("/", "\\")
    local normalizedFolderPath = normalizePath(folderPath)
    local fileName = getFileName(filePath)
    local candidates = {}

    for _, root in ipairs(LOCAL_MODULE_ROOTS) do
        local normalizedRoot = normalizePath(root)
        local backslashRoot = normalizedRoot:gsub("/", "\\")

        table.insert(candidates, normalizedRoot .. normalizedFilePath)
        table.insert(candidates, backslashRoot .. backslashFilePath)

        if normalizedFolderPath ~= "" then
            table.insert(candidates, normalizedRoot .. normalizedFolderPath .. "/" .. fileName)
            table.insert(candidates, backslashRoot .. normalizedFolderPath:gsub("/", "\\") .. "\\" .. fileName)
        end
    end

    local seen = {}
    local lastErr = nil

    for _, candidate in ipairs(candidates) do
        if not seen[candidate] then
            seen[candidate] = true

            local successRead, contentOrErr = pcall(readfile, candidate)
            if successRead and type(contentOrErr) == "string" and #contentOrErr > 0 then
                return contentOrErr, candidate
            end

            lastErr = contentOrErr
        end
    end

    return nil, nil, lastErr or "local readfile failed for all candidates"
end

local REMOTE_MODULE_BASE = "https://raw.githubusercontent.com/Ahlstarr-Mayjishan/Blackout-Revival/main/"
local ALLOW_REMOTE_MODULE_FALLBACK = false

local function encodeModulePath(path)
    return normalizePath(path):gsub(" ", "%%20")
end

local function fetchRemoteModuleFile(modulePath)
    if not ALLOW_REMOTE_MODULE_FALLBACK then
        return nil, nil, "remote fallback disabled; local file not found/readable"
    end

    local url = REMOTE_MODULE_BASE .. encodeModulePath(modulePath)
    local successFetch, contentOrErr = pcall(function()
        return game:HttpGet(url, true)
    end)

    if successFetch and type(contentOrErr) == "string" and #contentOrErr > 0 and contentOrErr ~= "404: Not Found" then
        return contentOrErr, url
    end

    return nil, url, contentOrErr
end

-- 5. Module Loading Mechanism
-- Create header section in UI
local ModulesSection = Tab:CreateSection("Loaded Modules")
Tabs.Status:CreateLabel("Safe boot: automation engines are not auto-loaded.")
Tabs.Status:CreateLabel("Use System controls first; load risky modules only after the base menu is stable.")
local LoadedModulePaths = {}

local function shouldShowModuleHeader(moduleIdentifier)
    local normalizedIdentifier = normalizePath(moduleIdentifier)
    return normalizedIdentifier:find("/Tab%.luau$")
        or normalizedIdentifier:find("/Control%.luau$")
        or normalizedIdentifier:find("/Aim Assist modes/")
end

local function getModuleTab(moduleIdentifier)
    local normalizedIdentifier = normalizePath(moduleIdentifier)

    if normalizedIdentifier:find("Aim Assits/Aim Assist modes/", 1, true) then
        return Tabs.AimModes
    end

    if normalizedIdentifier:find("Aim Assits/", 1, true) then
        return Tabs.Aim
    end

    if normalizedIdentifier:find("Loots/", 1, true) then
        return Tabs.Loots
    end

    if normalizedIdentifier:find("Player Modifier/Control.luau", 1, true)
        or normalizedIdentifier:find("Player Modifier/GC.luau", 1, true)
        or normalizedIdentifier:find("Player Modifier/PerformanceGuard.luau", 1, true) then
        return Tabs.System
    end

    if normalizedIdentifier:find("Player Modifier/", 1, true) then
        return Tabs.Player
    end

    return Tabs.Status
end

local function initModuleTable(moduleResult, moduleIdentifier, targetTab)
    if type(moduleResult) == "table" and type(moduleResult.Init) == "function" then
        local moduleTab = targetTab or getModuleTab(moduleIdentifier)
        local moduleName = moduleResult.Name or moduleIdentifier
        local moduleDesc = moduleResult.Description or "No description provided."
        
        if shouldShowModuleHeader(moduleIdentifier) then
            moduleTab:CreateSection(moduleName)
            if moduleResult.Description then
                moduleTab:CreateLabel(moduleDesc)
            end
        end
        
        local initSuccess, initErr = pcall(function()
            moduleResult:Init(moduleTab)
        end)
        
        if not initSuccess then
            warn("Main UI | Error initializing module '" .. moduleName .. "': " .. tostring(initErr))
            Tabs.Status:CreateLabel("Error: " .. moduleName .. " - " .. tostring(initErr))
        else
            print("Main UI | Loaded module: " .. moduleName)
            -- Add label to the main modules loaded list at the top
            Tabs.Status:CreateLabel("Loaded: " .. moduleName)
        end
    else
        warn("Main UI | Module " .. tostring(moduleIdentifier) .. " must return a table containing an 'Init' function.")
    end
end

local function loadModuleByPath(modulePath, targetTab)
    local normalizedModulePath = normalizePath(modulePath)

    if LoadedModulePaths[normalizedModulePath] then
        Tabs.Status:CreateLabel("Already loaded: " .. normalizedModulePath)
        return false
    end

    local folderPath = normalizedModulePath:match("^(.*)/[^/]+$") or ""
    local content = nil
    local sourcePath = nil
    local readErr = nil

    if type(readfile) == "function" then
        content, sourcePath, readErr = readModuleFile(folderPath, normalizedModulePath)
    end

    if not content then
        content, sourcePath, readErr = fetchRemoteModuleFile(normalizedModulePath)
    end

    if not content then
        warn("Main UI | Failed to load module file: " .. tostring(normalizedModulePath) .. " | " .. tostring(readErr))
        Tabs.Status:CreateLabel("Load failed: " .. normalizedModulePath)
        return false
    end

    local func, syntaxErr = loadstring(content)
    if not func then
        warn("Main UI | Syntax error in module '" .. tostring(sourcePath or normalizedModulePath) .. "': " .. tostring(syntaxErr))
        Tabs.Status:CreateLabel("Syntax error: " .. normalizedModulePath)
        return false
    end

    local execSuccess, moduleResult = pcall(func)
    if not execSuccess then
        warn("Main UI | Runtime error in module '" .. tostring(sourcePath or normalizedModulePath) .. "': " .. tostring(moduleResult))
        Tabs.Status:CreateLabel("Runtime error: " .. normalizedModulePath)
        return false
    end

    LoadedModulePaths[normalizedModulePath] = true
    initModuleTable(moduleResult, normalizedModulePath, targetTab)
    return true
end

local function loadModuleGroup(groupName, modulePaths)
    Tabs.Status:CreateLabel("Loading group: " .. groupName)

    local loadedCount = 0
    for _, modulePath in ipairs(modulePaths) do
        if loadModuleByPath(modulePath) then
            loadedCount = loadedCount + 1
        end
    end

    Tabs.Status:CreateLabel("Group done: " .. groupName .. " (" .. tostring(loadedCount) .. " new)")
end

_G.BlackoutLoadModule = function(modulePath)
    return loadModuleByPath(modulePath)
end

local function createEngineLoadControls()
    local ok, err = pcall(function()
        Tabs.System:CreateSection("Manual Engine Loading")
        Tabs.System:CreateLabel("Safe Boot loads only tabs and cleanup controls. Load one group at a time.")

        Tabs.System:CreateButton({
            Name = "Load Movement Engines",
            Callback = function()
                loadModuleGroup("Movement Engines", {
                    "Player Modifier/PerformanceGuard.luau",
                    "Player Modifier/DoubleJump.luau",
                    "Player Modifier/NoFallDamage.luau",
                    "Player Modifier/AntiRagdoll.luau",
                    "Player Modifier/AutoUnlock.luau",
                    "Player Modifier/BetterMovement.luau",
                    "Player Modifier/InfiniteStamina.luau",
                    "Player Modifier/SpeedHack.luau",
                })
            end,
        })

        Tabs.System:CreateButton({
            Name = "Load Combat Engines",
            Callback = function()
                loadModuleGroup("Combat Engines", {
                    "Player Modifier/Killaura.luau",
                    "Player Modifier/AuraActions.luau",
                    "Player Modifier/AutoBash.luau",
                    "Player Modifier/AntiFlashbang.luau",
                    "Player Modifier/Executor.luau",
                })
            end,
        })

        Tabs.System:CreateButton({
            Name = "Load Loot Engines",
            Callback = function()
                loadModuleGroup("Loot Engines", {
                    "Loots/AutoLockpick.luau",
                    "Loots/AutoCollect.luau",
                    "Loots/Executor.luau",
                })
            end,
        })

        Tabs.System:CreateButton({
            Name = "Load Aim Engines",
            Callback = function()
                loadModuleGroup("Aim Engines", {
                    "Aim Assits/Executor.luau",
                    "Aim Assits/Aim Assist modes/Aimbot.luau",
                    "Aim Assits/Aim Assist modes/SilentAim.luau",
                    "Aim Assits/Aim Assist modes/HomingBullets.luau",
                    "Aim Assits/Aim Assist modes/RecoilControl.luau",
                })
            end,
        })
    end)

    if not ok then
        warn("Main UI | Failed to create manual engine controls: " .. tostring(err))
    end
end

createEngineLoadControls()

-- Loader: Client Executor Environment (Workspace filesystem)
local function loadExecutorModules()
    local modulePaths = {
        "Player Modifier/Tab.luau",
        "Player Modifier/Control.luau",
        "Player Modifier/GC.luau",
        "Loots/Tab.luau",
        "Loots/Control.luau",
        "Loots/GC.luau",
        "Aim Assits/Tab.luau",
        "Aim Assits/Control.luau",
        "Aim Assits/GC.luau",
    }

    local modulesLoadedCount = 0

    for _, modulePath in ipairs(modulePaths) do
        if loadModuleByPath(modulePath) then
            modulesLoadedCount = modulesLoadedCount + 1
        end
    end

    if modulesLoadedCount == 0 then
        Tabs.Status:CreateLabel("No modules loaded from local workspace or GitHub.")
    end

    return true
end

-- Loader: Roblox Studio / Standard Fallback (ModuleScripts)
local function loadStudioModules()
    local modulesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("PlayerModifierModules") or workspace:FindFirstChild("PlayerModifierModules")
    
    if not modulesFolder then
        Tabs.Status:CreateLabel("No modules found. Create 'PlayerModifierModules' folder in ReplicatedStorage/Workspace to load local ModuleScripts.")
        return
    end
    
    local modulesLoadedCount = 0
    for _, child in ipairs(modulesFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local successRequire, moduleResult = pcall(require, child)
            if successRequire then
                initModuleTable(moduleResult, child.Name)
                modulesLoadedCount = modulesLoadedCount + 1
            else
                warn("Main UI | Studio failed to require ModuleScript '" .. child.Name .. "': " .. tostring(moduleResult))
            end
        end
    end
    
    if modulesLoadedCount == 0 then
        Tabs.Status:CreateLabel("No ModuleScripts found inside 'PlayerModifierModules'.")
    end
end

-- Start loading modules based on environment
local isExecutor = type(loadstring) == "function"
if isExecutor then
    print("Main UI | Executor environment detected. Loading modules from local workspace or GitHub.")
    loadExecutorModules()
else
    print("Main UI | Non-executor / Studio environment detected. Checking ReplicatedStorage / Workspace for PlayerModifierModules.")
    loadStudioModules()
end

-- 6. Initialize UI
sendNotification({
    Title = "Player Modifier",
    Content = "Main UI loaded successfully! Use _G.StopBlackoutUI() to unload.",
    Duration = 5,
    Image = 4483362458,
})
