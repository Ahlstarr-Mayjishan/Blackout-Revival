--[[
    ========================================================================
    Player Modifier - SpeedHack Module
    ========================================================================
    Enforces custom WalkSpeed values and bypasses in-game speed limiters.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local SpeedHack = {}
SpeedHack.Name = "Speed Hack Logic"
SpeedHack.Description = "Hooks humanoid WalkSpeed adjustments to enforce custom player speed."

function SpeedHack:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}

    -- 1. Hook __newindex for WalkSpeed adjustments via Metatable Hooking
    local hookSuccess, err = pcall(function()
        if not hookmetamethod then return end
        if _G.OriginalFunctions["WalkSpeed_NewIndex"] then return end

        local oldNewIndex
        oldNewIndex = hookmetamethod(game, "__newindex", function(self, key, value)
            if _G.ModifierStates and _G.ModifierStates.SpeedHackEnabled and key == "WalkSpeed" then
                if self:IsA("Humanoid") then
                    local character = LocalPlayer.Character
                    if character and self:IsDescendantOf(character) then
                        -- Replace assigned walk speed value with custom walk speed
                        value = _G.ModifierStates.CustomWalkSpeed or 16
                    end
                end
            end
            return oldNewIndex(self, key, value)
        end)

        _G.OriginalFunctions["WalkSpeed_NewIndex"] = oldNewIndex
        print("[Player Modifier - SpeedHack] Metatable __newindex hook successfully established.")
    end)

    if not hookSuccess then
        warn("[Player Modifier - SpeedHack] Failed to establish __newindex hook: " .. tostring(err))
    end

    -- 2. Setup a RenderStepped fallback loop (forces WalkSpeed physically in case of bypass failure)
    local speedLoopConnection = RunService.RenderStepped:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.SpeedHackEnabled then
            return
        end

        pcall(function()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local targetSpeed = _G.ModifierStates.CustomWalkSpeed or 16

            if humanoid and humanoid.WalkSpeed ~= targetSpeed then
                humanoid.WalkSpeed = targetSpeed
            end
        end)
    end)

    table.insert(_G.ModifierConnections, speedLoopConnection)
    print("[Player Modifier - SpeedHack] Initialized.")
end

return SpeedHack
