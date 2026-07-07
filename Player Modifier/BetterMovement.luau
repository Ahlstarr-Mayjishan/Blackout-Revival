--[[
    ========================================================================
    Player Modifier - BetterMovement Module (Inertia & Penalty Bypasser)
    ========================================================================
    This module implements fine-grained movement modifications:
        1. "Better Movement" -> Eliminates inertia/sliding on RenderStepped.
        2. "No Slowdown Aim" -> Removes movement speed penalties when aiming.
        3. "No Slowdown Block" -> Removes speed penalties when blocking or using items.
        4. "No Slowdown OverWeight" -> Removes speed penalties when carrying too much weight.
        5. "No Slowdown Broken Leg/Arm" -> Hooks limb attributes to ignore bone fracture slowdowns.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local BetterMovement = {}
BetterMovement.Name = "Better Movement Logic"
BetterMovement.Description = "Removes inertia, penalties (Aiming/Reloading/Blocking), and leg crippling movement limits."

-- Helper to safely log messages
local function log(msg)
    print("[Player Modifier - BetterMovement] " .. tostring(msg))
end

-- 1. No Inertia (Bypasses MovementHandler direction interpolation)
local function setupNoInertia()
    local connection = RunService.RenderStepped:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.BetterMovementOptions then
            return
        end
        
        -- Check if "Better Movement" is checked in dropdown options
        if not _G.ModifierStates.BetterMovementOptions["Better Movement"] then
            return
        end
        
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        
        -- If character is moving, force input direction to bypass inertia lerp
        if humanoid and humanoid.MoveDirection.Magnitude > 0 then
            humanoid:Move(humanoid.MoveDirection)
        end
    end)
    
    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, connection)
    end
    log("Instant direction controller registered.")
end

local function clearBrokenBoneAttributes(character)
    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:GetAttribute("BrokenBone") ~= nil then
            descendant:SetAttribute("BrokenBone", false)
        end
    end
end

local function setupStateSanitizer()
    local connection = RunService.RenderStepped:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.BetterMovementOptions then
            return
        end

        local opts = _G.ModifierStates.BetterMovementOptions
        local states = _G.CharacterStates

        if type(states) == "table" then
            if opts["Better Movement"] then
                states.NoSlide = true
            end

            if opts["No Slowdown Aim"] then
                states.AimingMovementSpeed = nil
            end

            if opts["No Slowdown Block"] then
                states.Blocking = false
                states.ServerBlocking = false
                states.UsingItem = false
            end

            if opts["No Slowdown OverWeight"] then
                states.OverWeightCapacity = 0
            end

            if opts["No Slowdown Broken Leg/Arm"] then
                states.Crippled = nil
            end
        end

        if opts["No Slowdown Broken Leg/Arm"] then
            clearBrokenBoneAttributes(LocalPlayer.Character)
        end
    end)

    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, connection)
    end

    log("Movement state sanitizer registered.")
end

-- Helper to wrap the CharacterStates table in a proxy metatable
local function wrapStatesTable(originalTable)
    if not originalTable or type(originalTable) ~= "table" then
        return originalTable
    end
    
    -- Check if it is already wrapped
    if getmetatable(originalTable) and getmetatable(originalTable).__isProxy then
        return originalTable
    end
    
    local proxy = setmetatable({}, {
        __isProxy = true,
        __index = function(_, k)
            if _G.ModifierStates and _G.ModifierStates.BetterMovementOptions then
                local opts = _G.ModifierStates.BetterMovementOptions
                
                -- 2. No Slowdown Aim
                if k == "AimingMovementSpeed" and opts["No Slowdown Aim"] then
                    return nil -- Returns nil so multiplier isn't applied
                end
                
                -- 3. No Slowdown Block
                if (k == "Blocking" or k == "ServerBlocking" or k == "UsingItem") and opts["No Slowdown Block"] then
                    -- Returning false prevents blocking slowdown states from triggering
                    return false
                end
                
                -- 4. No Slowdown OverWeight
                if k == "OverWeightCapacity" and opts["No Slowdown OverWeight"] then
                    return nil -- Returns nil so weight sum subtraction is bypassed
                end
            end
            return originalTable[k]
        end,
        __newindex = function(_, k, v)
            originalTable[k] = v
        end
    })
    
    return proxy
end

-- Intercept and proxy _G.CharacterStates assignments
local function setupStatesProxy()
    -- Wrap current if exists
    if _G.CharacterStates then
        _G.CharacterStates = wrapStatesTable(_G.CharacterStates)
        log("Proxy wrapped around existing _G.CharacterStates.")
    end
    
    -- Metatable hook on _G to wrap any future assignments to CharacterStates
    local mt = getmetatable(_G) or {}
    mt.__isProxy = true
    local oldNewIndex = mt.__newindex
    
    mt.__newindex = function(t, key, val)
        if key == "CharacterStates" and type(val) == "table" then
            local wrapped = wrapStatesTable(val)
            if oldNewIndex then
                oldNewIndex(t, key, wrapped)
            else
                rawset(t, key, wrapped)
            end
        else
            if oldNewIndex then
                oldNewIndex(t, key, val)
            else
                rawset(t, key, val)
            end
        end
    end
    
    setmetatable(_G, mt)
    log("Hooked _G.__newindex to intercept CharacterStates tables.")
end

function BetterMovement:Init(UIRef)
    -- Setup instant movement (No Inertia)
    setupNoInertia()
    setupStateSanitizer()
    
    -- Setup _G.CharacterStates proxy for Aim, Block, and Overweight capacity penalties
    setupStatesProxy()
    
    log("Better Movement module initialized.")
end

return BetterMovement
