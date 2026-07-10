--[[
    ========================================================================
    Loots - Tab Module
    ========================================================================
    UI and state database for loot-related helpers.
]]

local DEFAULT_LOOT_STATES = {
    AutoLockpick = false,
    AutoLockpickMode = "Legit",
    AutoLockpickLegitDelay = 1.15,
    AutoLockpickBlatantDelay = 0.08,
    AutoCollectLoot = false,
    CollectLootOptions = {
        Cash = true,
        Valuables = true,
    },
    CollectMode = "Legit",
}

local function mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = table.clone(value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            mergeDefaults(target[key], value)
        end
    end
end

local function firstOption(selectedOptions)
    if type(selectedOptions) == "string" then
        return selectedOptions
    end

    if type(selectedOptions) == "table" then
        return selectedOptions[1]
    end

    return nil
end

local function selectedLookup(selectedOptions)
    local lookup = {}

    if type(selectedOptions) == "string" then
        lookup[selectedOptions] = true
        return lookup
    end

    if type(selectedOptions) == "table" then
        for _, option in ipairs(selectedOptions) do
            lookup[option] = true
        end
    end

    return lookup
end

local function currentCollectOptions()
    local selected = {}
    local options = _G.LootStates and _G.LootStates.CollectLootOptions

    if type(options) ~= "table" then
        return { "Cash", "Valuables" }
    end

    if options.Cash then
        table.insert(selected, "Cash")
    end

    if options.Valuables then
        table.insert(selected, "Valuables")
    end

    return selected
end

_G.LootStates = _G.LootStates or {}
mergeDefaults(_G.LootStates, DEFAULT_LOOT_STATES)

_G.LootConnections = _G.LootConnections or {}
_G.LootRuntime = _G.LootRuntime or {}

local Tab = {}
Tab.Name = "Loots"
Tab.Description = "Loot and minigame automation controls."

function Tab:Init(UIRef)
    UIRef:CreateSection("Minigames")

    UIRef:CreateToggle({
        Name = "Auto Lockpick",
        CurrentValue = _G.LootStates.AutoLockpick,
        Flag = "Loots_AutoLockpick",
        Callback = function(Value)
            if _G.LootStates then
                _G.LootStates.AutoLockpick = Value
            end
            if Value and type(_G.BlackoutLoadModule) == "function" then
                _G.BlackoutLoadModule("Loots/AutoLockpick.luau")
            end
            print("[Loots - Tab] Auto Lockpick: " .. tostring(Value))
        end,
    })

    UIRef:CreateDropdown({
        Name = "Auto Lockpick Mode",
        Options = { "Legit", "Blatant" },
        CurrentOption = { _G.LootStates.AutoLockpickMode or "Legit" },
        MultipleOptions = false,
        Flag = "Loots_AutoLockpickMode",
        Callback = function(SelectedOptions)
            local option = firstOption(SelectedOptions)
            if _G.LootStates and (option == "Legit" or option == "Blatant") then
                _G.LootStates.AutoLockpickMode = option
            end
            print("[Loots - Tab] Auto Lockpick mode: " .. tostring(option))
        end,
    })

    UIRef:CreateSection("Collect")

    UIRef:CreateToggle({
        Name = "Auto Collect Loot",
        CurrentValue = _G.LootStates.AutoCollectLoot,
        Flag = "Loots_AutoCollectLoot",
        Callback = function(Value)
            if _G.LootStates then
                _G.LootStates.AutoCollectLoot = Value
            end
            if Value and type(_G.BlackoutLoadModule) == "function" then
                _G.BlackoutLoadModule("Loots/AutoCollect.luau")
            end
            print("[Loots - Tab] Auto Collect Loot: " .. tostring(Value))
        end,
    })

    UIRef:CreateDropdown({
        Name = "Loot Types",
        Options = { "Cash", "Valuables" },
        CurrentOption = currentCollectOptions(),
        MultipleOptions = true,
        Flag = "Loots_CollectLootOptions",
        Callback = function(SelectedOptions)
            if _G.LootStates then
                local lookup = selectedLookup(SelectedOptions)
                _G.LootStates.CollectLootOptions = {
                    Cash = lookup.Cash == true,
                    Valuables = lookup.Valuables == true,
                }
            end
            print("[Loots - Tab] Loot types updated.")
        end,
    })

    UIRef:CreateDropdown({
        Name = "Collect modes",
        Options = { "Legit", "Blatant" },
        CurrentOption = { _G.LootStates.CollectMode or "Legit" },
        MultipleOptions = false,
        Flag = "Loots_CollectMode",
        Callback = function(SelectedOptions)
            local option = firstOption(SelectedOptions)
            if _G.LootStates and (option == "Legit" or option == "Blatant") then
                _G.LootStates.CollectMode = option
            end
            print("[Loots - Tab] Collect mode: " .. tostring(option))
        end,
    })

    print("[Loots - Tab] Initialized.")
end

return Tab
