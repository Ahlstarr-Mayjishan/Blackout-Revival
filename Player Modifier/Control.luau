--[[
    ========================================================================
    Player Modifier - Control Module (UI and Orchestration Controller)
    ========================================================================
    This module coordinates the user interface by linking Rayfield UI toggles
    and buttons to the underlying Modifier States defined in Tab.luau.
    
    It also coordinates script unloading and cleanup via the GC.luau module.
]]

local Players = game:GetService("Players")

local Control = {}
Control.Name = "Control & Coordination"
Control.Description = "Main user controller that coordinates modifiers, configures states, and handles script unloading."

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

    -- 5. Button: Unload Script
    Tab:CreateButton({
        Name = "Unload / Clean up Script",
        Callback = function()
            print("[Player Modifier] Unloading script...")
            
            -- Require or load GC module to clean up
            local gcModule = nil
            local success, err = pcall(function()
                -- If in executor workspace environment, we read and execute GC.luau
                if readfile and isfile("Player Modifier/GC.luau") then
                    local content = readfile("Player Modifier/GC.luau")
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
