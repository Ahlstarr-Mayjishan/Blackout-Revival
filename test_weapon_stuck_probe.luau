--[[
    ========================================================================
    Blackout/Nightbound - Weapon Stuck Probe
    ========================================================================

    Purpose:
    - Diagnose why a gun/melee is equipped but cannot fire/use.
    - Logs equipped RayValue, GunStatus ammo fields, key CharacterStates, and
      active aim hook originals when MouseButton1 is pressed.

    Stop:
        _G.StopWeaponStuckProbe()
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

_G.WeaponStuckProbeActive = true

local connections = {}

local IMPORTANT_STATES = {
    "Aiming",
    "Blocking",
    "ServerBlocking",
    "UsingItem",
    "Reloading",
    "GunPreparing",
    "PreparingSwing",
    "Swinging",
    "Finishing",
    "DisableInventory",
    "ForceEquip",
    "E",
    "NT",
    "Endlag",
    "RestrictedMovement",
    "Downed",
    "Ragdolled",
}

local GUN_STATUS_ATTRIBUTES = {
    "Magazine",
    "Ammo",
    "MagazineCapacity",
    "SpareMagazines",
    "Mode",
    "FireMode",
    "Chambered",
    "Reloading",
    "Jammed",
    "Safety",
}

local function log(message)
    print("[WeaponProbe] " .. tostring(message))
end

local function addConnection(connection)
    table.insert(connections, connection)
    return connection
end

local function getEquippedRayValue()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("RayValue") then
            return child
        end
    end

    return nil
end

local function getStateSnapshot()
    local states = rawget(_G, "CharacterStates") or _G.CharacterStates
    local fields = {}

    if type(states) ~= "table" then
        return "CharacterStates=nil"
    end

    for _, key in ipairs(IMPORTANT_STATES) do
        local value = states[key]
        if value ~= nil and value ~= false then
            table.insert(fields, key .. "=" .. tostring(value))
        end
    end

    if #fields == 0 then
        return "no blocking states"
    end

    return table.concat(fields, ", ")
end

local function getGunStatusSnapshot(rayValue)
    if not rayValue then
        return "no equipped RayValue"
    end

    local gunStatus = rayValue:FindFirstChild("GunStatus")
    if not gunStatus then
        return "no GunStatus"
    end

    local fields = {}
    for _, key in ipairs(GUN_STATUS_ATTRIBUTES) do
        local value = gunStatus:GetAttribute(key)
        if value ~= nil then
            table.insert(fields, key .. "=" .. tostring(value))
        end
    end

    if #fields == 0 then
        return "GunStatus has no known attrs"
    end

    return table.concat(fields, ", ")
end

local function getHookSnapshot()
    local originals = _G.AimAssistOriginals
    if type(originals) ~= "table" then
        return "no AimAssistOriginals"
    end

    local fields = {}
    for _, key in ipairs({
        "FastCast_Fire",
        "HomingBullets_FastCast_Fire",
        "BulletHandler_Fire",
        "HomingBullets_BulletHandler_Fire",
        "Raycast_Metatable",
        "Raycast_Function",
    }) do
        if originals[key] ~= nil then
            table.insert(fields, key)
        end
    end

    if #fields == 0 then
        return "no active stored aim hooks"
    end

    return table.concat(fields, ", ")
end

local function dumpSnapshot(reason)
    local rayValue = getEquippedRayValue()
    log("==== " .. reason .. " ====")
    log("Equipped=" .. tostring(rayValue and rayValue.Name or nil) .. " class=" .. tostring(rayValue and rayValue.ClassName or nil))
    log("ToolAttr=" .. tostring(rayValue and rayValue:GetAttribute("Tool") or nil))
    log("GunStatus={" .. getGunStatusSnapshot(rayValue) .. "}")
    log("States={" .. getStateSnapshot() .. "}")
    log("Hooks={" .. getHookSnapshot() .. "}")
end

addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dumpSnapshot("M1 began gameProcessed=" .. tostring(gameProcessed))
    end
end))

addConnection(UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dumpSnapshot("M1 ended gameProcessed=" .. tostring(gameProcessed))
    end
end))

task.spawn(function()
    log("Started. Press Mouse1 while the weapon is stuck.")
    while _G.WeaponStuckProbeActive do
        task.wait(2)
        dumpSnapshot("periodic")
    end
end)

_G.StopWeaponStuckProbe = function()
    _G.WeaponStuckProbeActive = false

    for _, connection in ipairs(connections) do
        if typeof(connection) == "RBXScriptConnection" and connection.Connected then
            connection:Disconnect()
        end
    end

    table.clear(connections)
    log("Stopped.")
end
