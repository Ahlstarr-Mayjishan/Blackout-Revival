--[[
    ========================================================================
    Player Modifier - NoFallDamage Module
    ========================================================================
    Blocks the game's client-side fall/impact damage path without changing
    fall velocity or visible movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NoFallDamage = {}
NoFallDamage.Name = "No Fall Damage Logic"
NoFallDamage.Description = "Blocks fall damage remotes without changing movement."

local function isEnabled()
    return _G.ModifierStates and _G.ModifierStates.NoFallDamage == true
end

local function getPlayerRemote(remoteName)
    local events = ReplicatedStorage:FindFirstChild("Events")
    local playerEvents = events and events:FindFirstChild("Player")
    return playerEvents and playerEvents:FindFirstChild(remoteName)
end

local function isFallDamagePayload(args)
    if not isEnabled() then
        return false
    end

    -- Manual reset/give-up uses Damage(1000, { Head = 1000 }, nil, true).
    if args[4] == true then
        return false
    end

    -- RagdollClient landed fall damage:
    -- Damage(v22, { ["Right Leg"] = ..., ["Left Leg"] = ... }, true)
    if args[3] == true then
        return true
    end

    -- Do not block impact/ragdoll Damage(number, limbDamageTable).
    -- That path runs after the client enters physics/ragdoll and suppressing it
    -- can leave inventory/equip state stuck waiting for the normal recovery path.
    return false
end

local function setupDirectRemoteHooks()
    _G.OriginalFunctions = _G.OriginalFunctions or {}

    local damageRemote = getPlayerRemote("Damage")
    if damageRemote and hookmetamethod and not _G.OriginalFunctions["NoFallDamage_Namecall"] then
        local oldNamecall
        local callback = function(self, ...)
            if getnamecallmethod() == "FireServer" and self == damageRemote then
                local args = { ... }
                if isFallDamagePayload(args) then
                    return nil
                end
            end

            return oldNamecall(self, ...)
        end

        oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(callback) or callback)
        _G.OriginalFunctions["NoFallDamage_Namecall"] = oldNamecall
        print("[Player Modifier - NoFallDamage] Namecall Damage.FireServer hook installed.")
    end

    if not hookfunction then
        return
    end

    if damageRemote and not _G.OriginalFunctions["NoFallDamage_DamageFireServer"] then
        local originalDamage
        originalDamage = hookfunction(damageRemote.FireServer, function(self, ...)
            local args = { ... }
            if self == damageRemote and isFallDamagePayload(args) then
                return nil
            end

            return originalDamage(self, ...)
        end)

        _G.OriginalFunctions["NoFallDamage_DamageFireServer"] = originalDamage
        print("[Player Modifier - NoFallDamage] Direct Damage.FireServer hook installed.")
    end

end

function NoFallDamage:Init(UIRef)
    setupDirectRemoteHooks()
    print("[Player Modifier - NoFallDamage] Runtime protection initialized.")
end

return NoFallDamage
