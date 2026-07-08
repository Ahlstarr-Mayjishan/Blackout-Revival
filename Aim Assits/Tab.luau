--[[
    ========================================================================
    Aim Assits - Tab Module (Aim Assist Config Database & UI Toggles)
    ========================================================================
    This module initializes the global Aim Assist settings and builds the main
    interface controls on the Rayfield tab sheet.
]]

-- Initialize global state tables for Aim Assist if they do not exist
_G.AimAssistStates = _G.AimAssistStates or {
    Enabled = false,
    AimbotActive = false,
    SilentAimActive = false,
    HomingBulletsActive = false,
    AimType = "Player", -- "Player" or "Zombie (Nightbounds)"
    TargetPart = "Head", -- "Head" or "Torso"
    FOVRadius = 100,
    ShowFOV = false,
    Smoothing = 5, -- 1 = instant, higher = slower/smoother
    TeamCheck = true,
    WallCheck = true,
    IgnoredTargetNames = {
        ["Drone"] = true,
        ["Military Guard"] = true,
    },
}

_G.AimAssistStates.IgnoredTargetNames = _G.AimAssistStates.IgnoredTargetNames or {
    ["Drone"] = true,
    ["Military Guard"] = true,
}

if _G.AimAssistStates.RecoilControlActive == nil then
    _G.AimAssistStates.RecoilControlActive = false
end

if _G.AimAssistStates.RecoilMultiplier == nil then
    _G.AimAssistStates.RecoilMultiplier = 0
end

if _G.AimAssistStates.KickbackMultiplier == nil then
    _G.AimAssistStates.KickbackMultiplier = 0
end

if _G.AimAssistStates.SpreadMultiplier == nil then
    _G.AimAssistStates.SpreadMultiplier = 100
end

-- Connections register for GC cleanup
_G.AimAssistConnections = _G.AimAssistConnections or {}

-- Originals store for function hook restoration
_G.AimAssistOriginals = _G.AimAssistOriginals or {}

local Tab = {}
Tab.Name = "Aim Assist Settings"
Tab.Description = "Configures targeting parameters, field-of-view (FOV), team filters, and visibility checks."

function Tab:Init(UIRef)
    -- UIRef is the Rayfield Tab instance passed by Main UI.luau
    
    -- Create Section for Main Targeting
    UIRef:CreateSection("Targeting Options")

    -- 1. Toggle: Master Switch
    UIRef:CreateToggle({
        Name = "Enable Aim Assist",
        CurrentValue = _G.AimAssistStates.Enabled,
        Flag = "AimAssist_Enabled",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.Enabled = Value
            end
            print("[Aim Assist - Tab] Master state set to: " .. tostring(Value))
        end,
    })

    -- 1.5 Dropdown: Aim Type (Target Type Selection)
    UIRef:CreateDropdown({
        Name = "Aim Type",
        Options = {"Player", "Zombie (Nightbounds)"},
        CurrentOption = {_G.AimAssistStates.AimType},
        MultipleOptions = false,
        Flag = "AimAssist_AimType",
        Callback = function(SelectedOptions)
            local option = SelectedOptions[1] or SelectedOptions
            if _G.AimAssistStates and option then
                _G.AimAssistStates.AimType = option
            end
            print("[Aim Assist - Tab] Aim Type set to: " .. tostring(option))
        end,
    })

    -- 2. Dropdown: Target Body Part
    UIRef:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "Torso"},
        CurrentOption = {_G.AimAssistStates.TargetPart},
        MultipleOptions = false,
        Flag = "AimAssist_TargetPart",
        Callback = function(SelectedOptions)
            local option = SelectedOptions[1] or SelectedOptions
            if _G.AimAssistStates and option then
                _G.AimAssistStates.TargetPart = option
            end
            print("[Aim Assist - Tab] Target bone set to: " .. tostring(option))
        end,
    })

    -- 3. Slider: Smoothness Level
    UIRef:CreateSlider({
        Name = "Smoothness / Lerp Speed",
        Range = {1, 30},
        Increment = 1,
        CurrentValue = _G.AimAssistStates.Smoothing,
        Flag = "AimAssist_Smoothing",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.Smoothing = Value
            end
            print("[Aim Assist - Tab] Smoothing set to: " .. tostring(Value))
        end,
    })

    -- Create Section for FOV Circle
    UIRef:CreateSection("Field Of View (FOV) Settings")

    -- 4. Toggle: Show FOV
    UIRef:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = _G.AimAssistStates.ShowFOV,
        Flag = "AimAssist_ShowFOV",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.ShowFOV = Value
            end
            print("[Aim Assist - Tab] Show FOV circle: " .. tostring(Value))
        end,
    })

    -- 5. Slider: FOV Radius Size
    UIRef:CreateSlider({
        Name = "FOV Radius Size",
        Range = {20, 800},
        Increment = 10,
        CurrentValue = _G.AimAssistStates.FOVRadius,
        Flag = "AimAssist_FOVRadius",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.FOVRadius = Value
            end
            print("[Aim Assist - Tab] FOV Radius set to: " .. tostring(Value))
        end,
    })

    -- Create Section for Filters
    UIRef:CreateSection("Target Filters")

    -- 6. Toggle: Team Check
    UIRef:CreateToggle({
        Name = "Team Check (Ignore Allies)",
        CurrentValue = _G.AimAssistStates.TeamCheck,
        Flag = "AimAssist_TeamCheck",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.TeamCheck = Value
            end
            print("[Aim Assist - Tab] Team Check state: " .. tostring(Value))
        end,
    })

    -- 7. Toggle: Wall Check
    UIRef:CreateToggle({
        Name = "Wall Check (Ignore Behind Walls)",
        CurrentValue = _G.AimAssistStates.WallCheck,
        Flag = "AimAssist_WallCheck",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.WallCheck = Value
            end
            print("[Aim Assist - Tab] Wall Check state: " .. tostring(Value))
        end,
    })

    UIRef:CreateSection("Weapon Control")

    UIRef:CreateToggle({
        Name = "Enable Recoil Control",
        CurrentValue = _G.AimAssistStates.RecoilControlActive,
        Flag = "AimAssist_RecoilControlActive",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.RecoilControlActive = Value
            end
            print("[Aim Assist - Tab] Recoil Control: " .. tostring(Value))
        end,
    })

    UIRef:CreateSlider({
        Name = "Recoil %",
        Range = {0, 100},
        Increment = 5,
        CurrentValue = _G.AimAssistStates.RecoilMultiplier,
        Flag = "AimAssist_RecoilMultiplier",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.RecoilMultiplier = Value
            end
            print("[Aim Assist - Tab] Recoil multiplier: " .. tostring(Value) .. "%")
        end,
    })

    UIRef:CreateSlider({
        Name = "Kickback %",
        Range = {0, 100},
        Increment = 5,
        CurrentValue = _G.AimAssistStates.KickbackMultiplier,
        Flag = "AimAssist_KickbackMultiplier",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.KickbackMultiplier = Value
            end
            print("[Aim Assist - Tab] Kickback multiplier: " .. tostring(Value) .. "%")
        end,
    })

    UIRef:CreateSlider({
        Name = "Spread %",
        Range = {0, 100},
        Increment = 5,
        CurrentValue = _G.AimAssistStates.SpreadMultiplier,
        Flag = "AimAssist_SpreadMultiplier",
        Callback = function(Value)
            if _G.AimAssistStates then
                _G.AimAssistStates.SpreadMultiplier = Value
            end
            print("[Aim Assist - Tab] Spread multiplier: " .. tostring(Value) .. "%")
        end,
    })

    print("[Aim Assist - Tab] Configuration UI successfully initialized.")
end

return Tab
