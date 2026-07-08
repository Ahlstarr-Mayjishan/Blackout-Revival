--[[
    ========================================================================
    Player Modifier - SpeedHack Module
    ========================================================================
    Enforces custom WalkSpeed values and bypasses in-game speed limiters.
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local SpeedHack = {}
SpeedHack.Name = "Speed Hack Logic"
SpeedHack.Description = "Hooks humanoid WalkSpeed adjustments to enforce custom player speed."

function SpeedHack:Init(UIRef)
    _G.OriginalFunctions = _G.OriginalFunctions or {}
    _G.ModifierConnections = _G.ModifierConnections or {}
    _G.ModifierRuntime = _G.ModifierRuntime or {}

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

    if _G.ModifierRuntime.SpeedHackThread and coroutine.status(_G.ModifierRuntime.SpeedHackThread) ~= "dead" then
        print("[Player Modifier - SpeedHack] Speed fallback worker already running.")
        return
    end

    -- 2. Timed fallback loop. RenderStepped is unnecessary here and stacks badly after reloads.
    local speedLoopThread = task.spawn(function()
        while _G.ModifierStates do
            local delayTime = 0.05
            if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                delayTime = _G.PerformanceGuard.GetDelay(delayTime, "medium")
            end

            if _G.ModifierStates.SpeedHackEnabled then
                pcall(function()
                    local character = LocalPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local targetSpeed = _G.ModifierStates.CustomWalkSpeed or 16

                    if humanoid and humanoid.WalkSpeed ~= targetSpeed then
                        humanoid.WalkSpeed = targetSpeed
                    end
                end)
            end

            task.wait(delayTime)
        end
    end)

    _G.ModifierRuntime.SpeedHackThread = speedLoopThread
    table.insert(_G.ModifierConnections, speedLoopThread)
    print("[Player Modifier - SpeedHack] Initialized.")
end

return SpeedHack
