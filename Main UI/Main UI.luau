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

local function loadLocalGc(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" or not isfile(path) then
        return nil
    end

    local ok, result = pcall(function()
        return loadstring(readfile(path))()
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
        Tabs.System:CreateLabel("Console: _G.StopBlackoutUI()")
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

local function getFileName(path)
    return normalizePath(path):match("[^/]+$") or tostring(path)
end

local function readModuleFile(folderPath, filePath)
    local normalizedFilePath = normalizePath(filePath)
    local candidates = {
        filePath,
        normalizedFilePath,
        normalizePath(folderPath) .. "/" .. getFileName(filePath),
    }

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

    return nil, nil, lastErr
end

local REMOTE_MODULE_BASE = "https://raw.githubusercontent.com/Ahlstarr-Mayjishan/Blackout-Revival/main/"

local function encodeModulePath(path)
    return normalizePath(path):gsub(" ", "%%20")
end

local function fetchRemoteModuleFile(modulePath)
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

    if normalizedIdentifier:find("Player Modifier/Control.luau", 1, true) or normalizedIdentifier:find("Player Modifier/GC.luau", 1, true) then
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

-- Loader: Client Executor Environment (Workspace filesystem)
local function loadExecutorModules()
    local modulePaths = {
        "Player Modifier/Tab.luau",
        "Player Modifier/DoubleJump.luau",
        "Player Modifier/NoFallDamage.luau",
        "Player Modifier/AntiRagdoll.luau",
        "Player Modifier/AutoUnlock.luau",
        "Player Modifier/BetterMovement.luau",
        "Player Modifier/Killaura.luau",
        "Player Modifier/InfiniteStamina.luau",
        "Player Modifier/SpeedHack.luau",
        "Player Modifier/AuraActions.luau",
        "Player Modifier/AutoBash.luau",
        "Player Modifier/AntiFlashbang.luau",
        "Player Modifier/Control.luau",
        "Player Modifier/Executor.luau",
        "Player Modifier/GC.luau",
        "Aim Assits/Tab.luau",
        "Aim Assits/Control.luau",
        "Aim Assits/Executor.luau",
        "Aim Assits/GC.luau",
        "Aim Assits/Aim Assist modes/Aimbot.luau",
        "Aim Assits/Aim Assist modes/SilentAim.luau",
        "Aim Assits/Aim Assist modes/HomingBullets.luau",
    }

    local modulesLoadedCount = 0

    for _, modulePath in ipairs(modulePaths) do
        local folderPath = modulePath:match("^(.*)/[^/]+$") or ""
        local content = nil
        local sourcePath = nil
        local readErr = nil

        if type(readfile) == "function" then
            content, sourcePath, readErr = readModuleFile(folderPath, modulePath)
        end

        if not content then
            content, sourcePath, readErr = fetchRemoteModuleFile(modulePath)
        end

        if content then
            local func, syntaxErr = loadstring(content)
            if func then
                local execSuccess, moduleResult = pcall(func)
                if execSuccess then
                    initModuleTable(moduleResult, modulePath)
                    modulesLoadedCount = modulesLoadedCount + 1
                else
                    warn("Main UI | Runtime error in module '" .. tostring(sourcePath or modulePath) .. "': " .. tostring(moduleResult))
                end
            else
                warn("Main UI | Syntax error in module '" .. tostring(sourcePath or modulePath) .. "': " .. tostring(syntaxErr))
            end
        else
            warn("Main UI | Failed to load module file: " .. tostring(modulePath) .. " | " .. tostring(readErr))
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
