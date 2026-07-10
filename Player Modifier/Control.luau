--[[
    ========================================================================
    Player Modifier - Control Module (UI and Orchestration Controller)
    ========================================================================
    This module coordinates the user interface by linking Rayfield UI toggles
    and buttons to the underlying Modifier States defined in Tab.luau.
    
    It also coordinates script unloading and cleanup via the GC.luau module.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Control = {}
Control.Name = "Control & Coordination"
Control.Description = "Main user controller that coordinates modifiers, configures states, and handles script unloading."

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

local function readWorkspaceFile(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return nil
    end

    local candidates = {
        path,
        "BlackoutRevival/" .. path,
        "BlackoutRevival\\" .. path:gsub("/", "\\"),
    }

    for _, candidate in ipairs(candidates) do
        if isfile(candidate) then
            return readfile(candidate)
        end
    end

    return nil
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

local function repairServerGunModel()
    local character = Players.LocalPlayer.Character
    if not character then
        return false, "no character"
    end

    local serverGunModel = character:FindFirstChild("ServerGunModel")
    if not serverGunModel then
        return false, "no ServerGunModel"
    end

    local missing = {}
    for _, childName in ipairs({ "ShowCrosshair", "Unchambered", "Settings" }) do
        if not serverGunModel:FindFirstChild(childName) then
            table.insert(missing, childName)
        end
    end

    if #missing > 0 then
        warn("[Player Modifier - Control] ServerGunModel missing: " .. table.concat(missing, ", ") .. ". Runtime model was not patched.")
        return false, "missing " .. table.concat(missing, ", ")
    end

    return false, "ok"
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
        local falseStates = {
            "Blocking",
            "ServerBlocking",
            "UsingItem",
            "Reloading",
            "GunPreparing",
            "PreparingSwing",
            "Swinging",
            "Finishing",
        }

        for _, key in ipairs(falseStates) do
            pcall(function()
                states[key] = false
            end)
        end

        local nilStates = {
            "DisableInventory",
            "ForceEquip",
            "E",
            "NT",
            "Endlag",
            "RestrictedMovement",
        }

        for _, key in ipairs(nilStates) do
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

    pcall(function()
        local si = ReplicatedStorage:FindFirstChild("SI")
        if si and type(si.Fire) == "function" then
            si:Fire(true)
        end
    end)

    print("[Player Modifier - Control] Cleared stuck weapon/inventory states.")
end

function Control:Init(Tab)
    -- Verify states table is initialized
    if not _G.ModifierStates then
        warn("[Player Modifier - Control] States table (_G.ModifierStates) is not initialized. Trying fallback.")
        _G.ModifierStates = {
            DoubleJump = false,
            NoFallDamage = false,
            AntiRagdoll = false,
            AutoUnlock = false
        }
    end
    -- Create Section for Admin & Script Management
    Tab:CreateSection("Script Options")

    _G.FixBlackoutWeapon = clearStuckWeaponStates
    _G.RepairBlackoutWeaponRuntime = repairServerGunModel

    Tab:CreateButton({
        Name = "Fix Stuck Weapon / Inventory",
        Callback = function()
            clearStuckWeaponStates()
        end,
    })

    Tab:CreateButton({
        Name = "Diagnose Weapon Runtime",
        Callback = function()
            repairServerGunModel()
        end,
    })

    -- 5. Button: Unload Script
    Tab:CreateButton({
        Name = "Unload / Clean up Script",
        Callback = function()
            print("[Player Modifier] Unloading script...")
            
            -- Require or load GC module to clean up
            local gcModule = nil
            local success, err = pcall(function()
                -- If in executor workspace environment, we read and execute GC.luau
                local content = readWorkspaceFile("Player Modifier/GC.luau")
                if content then
                    gcModule = loadstring(content)()
                end
            end)
            
            -- Fallback: Use direct pcall call if GC was already registered in global or workspace
            if not gcModule and game:GetService("ReplicatedStorage"):FindFirstChild("PlayerModifierModules") then
                local gcObj = game:GetService("ReplicatedStorage").PlayerModifierModules:FindFirstChild("GC")
                if gcObj then
                    gcModule = require(gcObj)
                end
            end
            
            -- Execute clean up
            if gcModule and type(gcModule.cleanup) == "function" then
                gcModule.cleanup()
            elseif _G.ModifierConnections then
                -- Direct fallback cleanup if GC module could not be required
                warn("[Player Modifier - Control] GC module not found. Performing basic inline cleanup.")
                for _, conn in ipairs(_G.ModifierConnections) do
                    if typeof(conn) == "RBXScriptConnection" and conn.Connected then
                        conn:Disconnect()
                    end
                end
                table.clear(_G.ModifierConnections)
                _G.ModifierStates = nil
                _G.ModifierConnections = nil
                _G.OriginalFunctions = nil
            end
            
            -- Destroy the Rayfield UI Window
            -- (Rayfield library has a global :Destroy() function for cleanup)
            local rayfieldModule = nil
            local getRayfieldSuccess, rayfieldErr = pcall(function()
                return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
            end)
            
            if getRayfieldSuccess and rayfieldModule and type(rayfieldModule.Destroy) == "function" then
                rayfieldModule:Destroy()
            else
                -- Fallback: Search for the ScreenGui named "Rayfield" and destroy it
                local CoreGui = game:GetService("CoreGui")
                local rayfieldGui = nil
                if gethui then
                    rayfieldGui = gethui():FindFirstChild("Rayfield")
                end
                if not rayfieldGui then
                    rayfieldGui = CoreGui:FindFirstChild("Rayfield")
                end
                if not rayfieldGui and CoreGui:FindFirstChild("RobloxGui") then
                    rayfieldGui = CoreGui.RobloxGui:FindFirstChild("Rayfield")
                end
                if rayfieldGui then
                    rayfieldGui:Destroy()
                    print("[Player Modifier] Destroyed Rayfield UI ScreenGui.")
                else
                    warn("[Player Modifier] Rayfield UI ScreenGui not found for destruction.")
                end
            end
            
            print("[Player Modifier] Script unloaded successfully.")
        end,
    })

    print("[Player Modifier] Control module initialized with UI toggles.")
end

return Control
