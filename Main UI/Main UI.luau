--[[
    ========================================================================
    Player Modifier - Main UI (Tab-less & Module Loading System)
    ========================================================================
    Developed for: Player Modifier Suite
    UI Library: Rayfield UI Library (Sirius)
    
    This script initializes Rayfield UI, sets up a single-page view (no tabs),
    and dynamically loads client modules from the "Player Modifier" folder.
    
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

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

-- 1. Load Rayfield UI Library
local Rayfield = nil
local success, err = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if success and Rayfield then
    print("Main UI | Rayfield UI successfully loaded.")
else
    warn("Main UI | Failed to fetch Rayfield from remote URL, using local mockup/fallback: " .. tostring(err))
    -- Fallback/Mockup in case Rayfield cannot be loaded (for Studio testing)
    Rayfield = {
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

-- 3. Create a Single Tab (Required internally by Rayfield to host elements)
local Tab = Window:CreateTab("Main Settings", 4483362458)

-- 4. Programmatic Tab-less Override
-- This routine hides the tab bar (sidebar) and stretches the elements page to fill the UI
local function applyTablessLayout()
    task.spawn(function()
        local LocalPlayer = Players.LocalPlayer
        local rayfieldGui = nil
        
        -- Poll to find the Rayfield ScreenGui within parent hierarchy
        for i = 1, 100 do
            if gethui then
                rayfieldGui = gethui():FindFirstChild("Rayfield")
            end
            if not rayfieldGui then
                rayfieldGui = CoreGui:FindFirstChild("Rayfield")
            end
            if not rayfieldGui and CoreGui:FindFirstChild("RobloxGui") then
                rayfieldGui = CoreGui.RobloxGui:FindFirstChild("Rayfield")
            end
            if not rayfieldGui and LocalPlayer then
                local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
                if playerGui then
                    rayfieldGui = playerGui:FindFirstChild("Rayfield")
                end
            end
            if rayfieldGui then break end
            task.wait(0.1)
        end
        
        if rayfieldGui then
            local Main = rayfieldGui:WaitForChild("Main", 5)
            if Main then
                local TabList = Main:WaitForChild("TabList", 5)
                local Elements = Main:WaitForChild("Elements", 5)
                if TabList and Elements then
                    -- Hide the Tab Navigation Sidebar
                    TabList.Visible = false
                    
                    -- Stretch Elements Panel to fill the entire width & height (adjusting for Topbar height of ~45px)
                    Elements.Position = UDim2.new(0, 10, 0, 45)
                    Elements.Size = UDim2.new(1, -20, 1, -55)
                    
                    print("Main UI | Tab-less layout modifier applied successfully.")
                else
                    warn("Main UI | Internal frames (TabList/Elements) not found inside Rayfield.Main.")
                end
            else
                warn("Main UI | Main frame not found inside Rayfield ScreenGui.")
            end
        else
            warn("Main UI | Rayfield ScreenGui not found. Skipping Tab-less modification.")
        end
    end)
end

applyTablessLayout()

-- 5. Module Loading Mechanism
-- Create header section in UI
local ModulesSection = Tab:CreateSection("Loaded Modules")

local function initModuleTable(moduleResult, moduleIdentifier)
    if type(moduleResult) == "table" and type(moduleResult.Init) == "function" then
        local moduleName = moduleResult.Name or moduleIdentifier
        local moduleDesc = moduleResult.Description or "No description provided."
        
        -- Create a UI section for this module to separate its elements visually
        local ModuleHeader = Tab:CreateSection("Module: " .. moduleName)
        if moduleResult.Description then
            Tab:CreateLabel(moduleDesc)
        end
        
        local initSuccess, initErr = pcall(function()
            moduleResult:Init(Tab)
        end)
        
        if not initSuccess then
            warn("Main UI | Error initializing module '" .. moduleName .. "': " .. tostring(initErr))
            Tab:CreateLabel("Error initializing: " .. tostring(initErr))
        else
            print("Main UI | Loaded module: " .. moduleName)
            -- Add label to the main modules loaded list at the top
            Tab:CreateLabel("✓ " .. moduleName .. " - Active")
        end
    else
        warn("Main UI | Module " .. tostring(moduleIdentifier) .. " must return a table containing an 'Init' function.")
    end
end

-- Loader: Client Executor Environment (Workspace filesystem)
local function loadExecutorModules()
    if not isfolder or not makefolder or not listfiles or not readfile then
        return false
    end
    
    local foldersToScan = {
        "Player Modifier",
        "Aim Assits",
        "Aim Assits/Aim Assist modes"
    }
    
    -- Ensure folders exist
    for _, folder in ipairs(foldersToScan) do
        if not isfolder(folder) then
            makefolder(folder)
            print("Main UI | Created '" .. folder .. "' directory in executor workspace.")
        end
    end
    
    local modulesLoadedCount = 0
    
    for _, folderPath in ipairs(foldersToScan) do
        local files = listfiles(folderPath)
        for _, filePath in ipairs(files) do
            local isLuaFile = filePath:sub(-4) == ".lua" or filePath:sub(-5) == ".luau"
            if isLuaFile then
                local successRead, content = pcall(readfile, filePath)
                if successRead and content and #content > 0 then
                    local func, syntaxErr = loadstring(content)
                    if func then
                        local execSuccess, moduleResult = pcall(func)
                        if execSuccess then
                            initModuleTable(moduleResult, filePath)
                            modulesLoadedCount = modulesLoadedCount + 1
                        else
                            warn("Main UI | Runtime error in module '" .. filePath .. "': " .. tostring(moduleResult))
                        end
                    else
                        warn("Main UI | Syntax error in module '" .. filePath .. "': " .. tostring(syntaxErr))
                    end
                else
                    warn("Main UI | Failed to read module file or file is empty: " .. filePath)
                end
            end
        end
    end
    
    if modulesLoadedCount == 0 then
        Tab:CreateLabel("No modules found in executor workspace directories.")
    end
    
    return true
end

-- Loader: Roblox Studio / Standard Fallback (ModuleScripts)
local function loadStudioModules()
    local modulesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("PlayerModifierModules") or workspace:FindFirstChild("PlayerModifierModules")
    
    if not modulesFolder then
        Tab:CreateLabel("No modules found. Create 'PlayerModifierModules' folder in ReplicatedStorage/Workspace to load local ModuleScripts.")
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
        Tab:CreateLabel("No ModuleScripts found inside 'PlayerModifierModules'.")
    end
end

-- Start loading modules based on environment
local isExecutor = pcall(function() return isfolder("Player Modifier") end)
if isExecutor then
    print("Main UI | Executor environment detected. Loading from workspace/Player Modifier.")
    loadExecutorModules()
else
    print("Main UI | Non-executor / Studio environment detected. Checking ReplicatedStorage / Workspace for PlayerModifierModules.")
    loadStudioModules()
end

-- 6. Initialize UI
Rayfield:Notify({
    Title = "Player Modifier",
    Content = "Main UI loaded successfully!",
    Duration = 5,
    Image = 4483362458,
})
