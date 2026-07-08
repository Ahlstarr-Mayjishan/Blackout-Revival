--[[
    ========================================================================
    Player Modifier - Tab Module (State and UI Toggles Database)
    ========================================================================
    This module initializes the global states and creates the 4 main feature
    toggles on the Rayfield UI.
    
    Toggles created:
        1. Infinite Double Jump (connected to _G.ModifierStates.DoubleJump)
        2. No Fall Damage (connected to _G.ModifierStates.NoFallDamage)
        3. Anti-Ragdoll (connected to _G.ModifierStates.AntiRagdoll)
        4. Auto-Unlock Safes & Doors (connected to _G.ModifierStates.AutoUnlock)
]]

local DEFAULT_MODIFIER_STATES = {
    DoubleJump = false,
    NoFallDamage = false,
    AntiRagdoll = false,
    AutoUnlock = false,
    Killaura = false,
    KillauraMode = "Legit",
    KillauraHitAt = "head",
    KillauraRange = 15,
    KillauraDelay = 0.2, -- attack delay in seconds
    BetterMovementOptions = {
        ["Better Movement"] = false,
        ["No Slowdown Aim"] = false,
        ["No Slowdown Block"] = false,
        ["No Slowdown OverWeight"] = false,
        ["No Slowdown Broken Leg/Arm"] = false
    },
    InfiniteStamina = false,
    SpeedHackEnabled = false,
    CustomWalkSpeed = 16,
    ReviveAura = false,
    ReviveAuraRange = 20,
    FinisherAura = false,
    FinisherAuraRange = 15,
    AutoBash = false,
    AutoBashEnemies = true,
    AntiFlashbang = false
}

local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function normalizeSelectedOptions(selectedOptions)
    if type(selectedOptions) == "string" then
        return { selectedOptions }
    end

    if type(selectedOptions) ~= "table" then
        return {}
    end

    local normalized = {}
    for _, option in ipairs(selectedOptions) do
        if type(option) == "string" then
            table.insert(normalized, option)
        end
    end

    if #normalized == 0 then
        for option, selected in pairs(selectedOptions) do
            if type(option) == "string" and selected == true then
                table.insert(normalized, option)
            elseif type(selected) == "string" then
                table.insert(normalized, selected)
            end
        end
    end

    return normalized
end

-- Initialize global state tables if they do not exist, and merge newly added defaults
-- when the UI is reloaded over an older in-memory state table.
_G.ModifierStates = _G.ModifierStates or {}
mergeDefaults(_G.ModifierStates, DEFAULT_MODIFIER_STATES)

-- Store connections here so they can be cleaned up by GC.luau
_G.ModifierConnections = _G.ModifierConnections or {}

-- Store original functions for hook restoration
_G.OriginalFunctions = _G.OriginalFunctions or {}

local Tab = {}
Tab.Name = "UI Tab Toggles"
Tab.Description = "Exposes the main modifier toggles to the user interface."

function Tab:Init(UIRef)
    -- UIRef is the Rayfield Tab instance passed by Main UI.luau
    
    -- Create Section for Movement & Physics
    UIRef:CreateSection("Movement & Physics")

    -- Toggle: Infinite Stamina
    UIRef:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = _G.ModifierStates.InfiniteStamina,
        Flag = "InfiniteStamina_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.InfiniteStamina = Value
            end
            print("[Player Modifier - Tab] Infinite Stamina state: " .. tostring(Value))
        end,
    })

    -- Toggle: Speed Hack
    UIRef:CreateToggle({
        Name = "Enable Speed Hack",
        CurrentValue = _G.ModifierStates.SpeedHackEnabled,
        Flag = "SpeedHackEnabled_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.SpeedHackEnabled = Value
            end
            print("[Player Modifier - Tab] Speed Hack state: " .. tostring(Value))
        end,
    })

    -- Slider: Custom WalkSpeed
    UIRef:CreateSlider({
        Name = "Custom WalkSpeed",
        Range = {16, 120},
        Increment = 1,
        CurrentValue = _G.ModifierStates.CustomWalkSpeed or 16,
        Flag = "CustomWalkSpeed_Slider",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.CustomWalkSpeed = Value
            end
            print("[Player Modifier - Tab] Custom WalkSpeed set to: " .. tostring(Value))
        end,
    })

    -- 1. Toggle: Infinite Double Jump
    UIRef:CreateToggle({
        Name = "Infinite Double Jump",
        CurrentValue = _G.ModifierStates.DoubleJump,
        Flag = "DoubleJump_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.DoubleJump = Value
            end
            print("[Player Modifier - Tab] Infinite Double Jump state: " .. tostring(Value))
        end,
    })

    -- 2. Toggle: No Fall Damage
    UIRef:CreateToggle({
        Name = "No Fall Damage",
        CurrentValue = _G.ModifierStates.NoFallDamage,
        Flag = "NoFallDamage_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.NoFallDamage = Value
            end
            print("[Player Modifier - Tab] No Fall Damage state: " .. tostring(Value))
        end,
    })

    -- 3. Toggle: Anti-Ragdoll
    UIRef:CreateToggle({
        Name = "Anti-Ragdoll (No Fall/Slam)",
        CurrentValue = _G.ModifierStates.AntiRagdoll,
        Flag = "AntiRagdoll_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.AntiRagdoll = Value
            end
            print("[Player Modifier - Tab] Anti-Ragdoll state: " .. tostring(Value))
        end,
    })

    -- 4. Dropdown: Better Movement Customizer
    UIRef:CreateDropdown({
        Name = "Better Movement Customizer",
        Options = {
            "Better Movement",
            "No Slowdown Aim",
            "No Slowdown Block",
            "No Slowdown OverWeight",
            "No Slowdown Broken Leg/Arm"
        },
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "BetterMovement_Dropdown",
        Callback = function(SelectedOptions)
            if _G.ModifierStates and _G.ModifierStates.BetterMovementOptions then
                local normalizedOptions = normalizeSelectedOptions(SelectedOptions)

                -- Clear previous selections
                for key, _ in pairs(_G.ModifierStates.BetterMovementOptions) do
                    _G.ModifierStates.BetterMovementOptions[key] = false
                end
                
                -- Update based on new selections
                for _, option in ipairs(normalizedOptions) do
                    if _G.ModifierStates.BetterMovementOptions[option] ~= nil then
                        _G.ModifierStates.BetterMovementOptions[option] = true
                    end
                end
            end
            print("[Player Modifier - Tab] Better Movement selected options updated.")
        end,
    })

    -- Create Section for Exploits
    UIRef:CreateSection("Exploits")

    -- 5. Toggle: Auto-Unlock Safes & Doors
    UIRef:CreateToggle({
        Name = "Auto-Unlock Safes & Doors",
        CurrentValue = _G.ModifierStates.AutoUnlock,
        Flag = "AutoUnlock_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.AutoUnlock = Value
            end
            print("[Player Modifier - Tab] Auto-Unlock state: " .. tostring(Value))
        end,
    })

    -- Create Section for Aura Actions
    UIRef:CreateSection("Aura Actions")

    -- Toggle: Revive Aura
    UIRef:CreateToggle({
        Name = "Revive Aura (Auto Revive Teammates)",
        CurrentValue = _G.ModifierStates.ReviveAura,
        Flag = "ReviveAura_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.ReviveAura = Value
            end
            print("[Player Modifier - Tab] Revive Aura state: " .. tostring(Value))
        end,
    })

    -- Slider: Revive Aura Range
    UIRef:CreateSlider({
        Name = "Revive Aura Range (Studs)",
        Range = {5, 50},
        Increment = 1,
        CurrentValue = _G.ModifierStates.ReviveAuraRange or 20,
        Flag = "ReviveAuraRange_Slider",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.ReviveAuraRange = Value
            end
            print("[Player Modifier - Tab] Revive Aura Range set to: " .. tostring(Value))
        end,
    })

    -- Button: Self Revive
    UIRef:CreateButton({
        Name = "Self-Revive (Instant Self Rescue)",
        Callback = function()
            local character = game.Players.LocalPlayer.Character
            local reviveRemote = game.ReplicatedStorage:FindFirstChild("Events")
                and game.ReplicatedStorage.Events:FindFirstChild("Actions")
                and game.ReplicatedStorage.Events.Actions:FindFirstChild("Revive")
            if character and reviveRemote then
                pcall(function()
                    reviveRemote:FireServer(character)
                end)
                print("[Player Modifier - Tab] Dispatched self-revive RemoteEvent call.")
            else
                warn("[Player Modifier - Tab] Failed to execute self-revive (Remote or Character missing).")
            end
        end,
    })

    -- Toggle: Finisher Aura
    UIRef:CreateToggle({
        Name = "Finisher Aura (Auto Execute Enemies)",
        CurrentValue = _G.ModifierStates.FinisherAura,
        Flag = "FinisherAura_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.FinisherAura = Value
            end
            print("[Player Modifier - Tab] Finisher Aura state: " .. tostring(Value))
        end,
    })

    -- Slider: Finisher Aura Range
    UIRef:CreateSlider({
        Name = "Finisher Aura Range (Studs)",
        Range = {5, 30},
        Increment = 1,
        CurrentValue = _G.ModifierStates.FinisherAuraRange or 15,
        Flag = "FinisherAuraRange_Slider",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.FinisherAuraRange = Value
            end
            print("[Player Modifier - Tab] Finisher Aura Range set to: " .. tostring(Value))
        end,
    })

    -- Create Section for Bashing
    UIRef:CreateSection("Auto-Bash")

    -- Toggle: Auto-Bash Doors/Enemies
    UIRef:CreateToggle({
        Name = "Auto-Bash (Doors & Melee Push)",
        CurrentValue = _G.ModifierStates.AutoBash,
        Flag = "AutoBash_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.AutoBash = Value
            end
            print("[Player Modifier - Tab] Auto-Bash state: " .. tostring(Value))
        end,
    })

    -- Toggle: Auto-Bash Enemies
    UIRef:CreateToggle({
        Name = "Bash Nearby Enemies",
        CurrentValue = _G.ModifierStates.AutoBashEnemies,
        Flag = "AutoBashEnemies_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.AutoBashEnemies = Value
            end
            print("[Player Modifier - Tab] Auto-Bash Enemies state: " .. tostring(Value))
        end,
    })

    -- Create Section for Immunity
    UIRef:CreateSection("Immunity")

    -- Toggle: Anti-Flashbang
    UIRef:CreateToggle({
        Name = "Anti-Flashbang & Anti-Concussion",
        CurrentValue = _G.ModifierStates.AntiFlashbang,
        Flag = "AntiFlashbang_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.AntiFlashbang = Value
            end
            print("[Player Modifier - Tab] Anti-Flashbang state: " .. tostring(Value))
        end,
    })

    -- Create Section for Melee Combat
    UIRef:CreateSection("Melee Combat")

    -- 6. Toggle: Kill Aura (Melee)
    UIRef:CreateToggle({
        Name = "Kill Aura (Melee)",
        CurrentValue = _G.ModifierStates.Killaura,
        Flag = "Killaura_Toggle",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.Killaura = Value
            end
            print("[Player Modifier - Tab] Kill Aura active state: " .. tostring(Value))
        end,
    })

    -- 6.5 Slider: Kill Aura Attack Delay (0 to 2s)
    UIRef:CreateSlider({
        Name = "Attack Delay (Seconds)",
        Range = {0, 20},
        Increment = 1,
        CurrentValue = math.floor((_G.ModifierStates.KillauraDelay or 0.2) * 10),
        Flag = "KillauraDelay_Slider",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.KillauraDelay = Value / 10
            end
            print("[Player Modifier - Tab] Kill Aura Delay set to: " .. tostring(Value / 10) .. "s")
        end,
    })

    -- 7. Dropdown: Kill Aura Mode
    UIRef:CreateDropdown({
        Name = "Kill Aura Mode",
        Options = {"Legit", "Blatant"},
        CurrentOption = {_G.ModifierStates.KillauraMode},
        MultipleOptions = false,
        Flag = "KillauraMode_Dropdown",
        Callback = function(SelectedOptions)
            local option = SelectedOptions[1] or SelectedOptions
            if _G.ModifierStates and option then
                _G.ModifierStates.KillauraMode = option
            end
            print("[Player Modifier - Tab] Kill Aura Mode set to: " .. tostring(option))
        end,
    })

    -- 8. Dropdown: Hit at
    UIRef:CreateDropdown({
        Name = "Hit at",
        Options = {"off", "head", "torso"},
        CurrentOption = {_G.ModifierStates.KillauraHitAt},
        MultipleOptions = false,
        Flag = "KillauraHitAt_Dropdown",
        Callback = function(SelectedOptions)
            local option = SelectedOptions[1] or SelectedOptions
            if _G.ModifierStates and option then
                _G.ModifierStates.KillauraHitAt = option
            end
            print("[Player Modifier - Tab] Kill Aura Hit target set to: " .. tostring(option))
        end,
    })

    -- 8.5 Slider: Kill Aura Range
    UIRef:CreateSlider({
        Name = "Kill Aura Range (Studs)",
        Range = {5, 30},
        Increment = 1,
        CurrentValue = _G.ModifierStates.KillauraRange or 15,
        Flag = "KillauraRange_Slider",
        Callback = function(Value)
            if _G.ModifierStates then
                _G.ModifierStates.KillauraRange = Value
            end
            print("[Player Modifier - Tab] Kill Aura Range set to: " .. tostring(Value))
        end,
    })

    print("[Player Modifier - Tab] Feature options successfully registered.")
end

return Tab
