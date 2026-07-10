--[[
    ========================================================================
    Player Modifier - NoFallDamage Module
    ========================================================================
    Blocks the game's client-side fall/impact damage path without changing
    fall velocity or visible movement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

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

    -- Ragdoll/impact damage:
    -- Damage(number, limbDamageTable)
    return type(args[1]) == "number" and type(args[2]) == "table"
end

local function setupDirectRemoteHooks()
    _G.OriginalFunctions = _G.OriginalFunctions or {}

    if not hookfunction then
        return
    end

    local damageRemote = getPlayerRemote("Damage")
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

    local ragdollRemote = getPlayerRemote("Ragdoll")
    if ragdollRemote and not _G.OriginalFunctions["NoFallDamage_RagdollFireServer"] then
        local originalRagdoll
        originalRagdoll = hookfunction(ragdollRemote.FireServer, function(self, ...)
            if self == ragdollRemote and isEnabled() then
                return nil
            end

            return originalRagdoll(self, ...)
        end)

        _G.OriginalFunctions["NoFallDamage_RagdollFireServer"] = originalRagdoll
        print("[Player Modifier - NoFallDamage] Direct Ragdoll.FireServer hook installed.")
    end
end

local function setupStateGuard()
    _G.ModifierRuntime = _G.ModifierRuntime or {}
    if _G.ModifierRuntime.NoFallDamageStateConnection
        and _G.ModifierRuntime.NoFallDamageStateConnection.Connected then
        return
    end

    local connection = RunService.Heartbeat:Connect(function()
        if not isEnabled() then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if _G.CharacterStates then
            _G.CharacterStates.Falling = false
            _G.CharacterStates.Ragdolled = false
            _G.CharacterStates.InPhysics = false
        end

        if character then
            character:SetAttribute("Falling", false)
            character:SetAttribute("CS", false)
            character:SetAttribute("Ragdolled", false)
            character:SetAttribute("InPhysics", false)
        end

        if humanoid then
            humanoid.PlatformStand = false
            if humanoid:GetState() == Enum.HumanoidStateType.Physics
                or humanoid:GetState() == Enum.HumanoidStateType.FallingDown then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    end)

    _G.ModifierRuntime.NoFallDamageStateConnection = connection
    _G.ModifierConnections = _G.ModifierConnections or {}
    table.insert(_G.ModifierConnections, connection)
    print("[Player Modifier - NoFallDamage] State guard connected.")
end

function NoFallDamage:Init(UIRef)
    setupDirectRemoteHooks()
    setupStateGuard()
    print("[Player Modifier - NoFallDamage] Runtime protection initialized.")
end

return NoFallDamage
