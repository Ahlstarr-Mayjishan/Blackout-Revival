--[[
    ========================================================================
    Aim Assits - Control Module (UI Control and Script Unloader)
    ========================================================================
    This module coordinates script options and handles clean termination of
    the Aim Assist suite.
]]

local Control = {}
Control.Name = "Control & Coordination"
Control.Description = "Exposes administrative options and termination sequences for the Aim Assist suite."

function Control:Init(Tab)
    -- Create Section for Admin & Script Management
    Tab:CreateSection("Aim Assist Suite Options")

    -- Button: Unload Script
    Tab:CreateButton({
        Name = "Unload / Clean up Aim Assist",
        Callback = function()
            print("[Aim Assist - Control] Triggering clean up sequence...")
            
            local gcModule = nil
            local success, err = pcall(function()
                -- If in executor workspace environment, we read and execute GC.luau
                if readfile and isfile("Aim Assits/GC.luau") then
                    local content = readfile("Aim Assits/GC.luau")
                    gcModule = loadstring(content)()
                end
            end)
            
            -- Fallback require
            if not gcModule and game:GetService("ReplicatedStorage"):FindFirstChild("AimAssistModules") then
                local gcObj = game:GetService("ReplicatedStorage").AimAssistModules:FindFirstChild("GC")
                if gcObj then
                    gcModule = require(gcObj)
                end
            end
            
            -- Execute clean up
            if gcModule and type(gcModule.cleanup) == "function" then
                gcModule.cleanup()
            elseif _G.AimAssistConnections then
                warn("[Aim Assist - Control] GC module not found. Performing basic inline cleanup.")
                for _, conn in ipairs(_G.AimAssistConnections) do
                    if typeof(conn) == "RBXScriptConnection" and conn.Connected then
                        conn:Disconnect()
                    end
                end
                table.clear(_G.AimAssistConnections)
                _G.AimAssistStates = nil
                _G.AimAssistConnections = nil
                _G.AimAssistOriginals = nil
            end
            
            print("[Aim Assist - Control] Aim Assist suite successfully unloaded.")
        end,
    })
    
    print("[Aim Assist - Control] Coordinator option registered successfully.")
end

return Control
