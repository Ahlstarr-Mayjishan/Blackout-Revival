--[[
    ========================================================================
    Loots - Instant Interact
    ========================================================================
    Removes ProximityPrompt hold time while enabled.

    This does not auto-trigger prompts. It only makes normal interact presses
    complete instantly, which is safer around shops, stations, and mission UI.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local InstantInteract = {}
InstantInteract.Name = "Instant Interact"
InstantInteract.Description = "Makes ProximityPrompt interactions complete without holding the key."

local function log(message)
    print("[Loots - InstantInteract] " .. tostring(message))
end

local function isEnabled()
    return _G.LootStates and _G.LootStates.InstantInteract == true
end

local function getOriginals()
    _G.LootRuntime = _G.LootRuntime or {}
    _G.LootRuntime.InstantInteractOriginalDurations = _G.LootRuntime.InstantInteractOriginalDurations or {}
    return _G.LootRuntime.InstantInteractOriginalDurations
end

local function rememberPrompt(prompt)
    local originals = getOriginals()
    if originals[prompt] == nil then
        originals[prompt] = prompt.HoldDuration
    end
end

local function patchPrompt(prompt)
    if not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") then
        return
    end

    rememberPrompt(prompt)

    if prompt.HoldDuration ~= 0 then
        prompt.HoldDuration = 0
    end
end

local function restorePrompt(prompt, originalDuration)
    if not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") then
        return
    end

    if type(originalDuration) == "number" then
        prompt.HoldDuration = originalDuration
    end
end

local function restoreAllPrompts()
    local originals = getOriginals()
    for prompt, originalDuration in pairs(originals) do
        restorePrompt(prompt, originalDuration)
    end
end

local function patchVisiblePrompts()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            patchPrompt(descendant)
        end
    end
end

local function setupPromptListener()
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}

    if _G.LootRuntime.InstantInteractPromptConnection
        and _G.LootRuntime.InstantInteractPromptConnection.Connected then
        return
    end

    local connection = ProximityPromptService.PromptShown:Connect(function(prompt)
        if isEnabled() then
            patchPrompt(prompt)
        end
    end)

    _G.LootRuntime.InstantInteractPromptConnection = connection
    table.insert(_G.LootConnections, connection)
end

local function setupStateLoop()
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}

    if _G.LootRuntime.InstantInteractThread
        and coroutine.status(_G.LootRuntime.InstantInteractThread) ~= "dead" then
        return
    end

    local thread = task.spawn(function()
        local wasEnabled = false

        while _G.LootStates do
            if isEnabled() then
                patchVisiblePrompts()
                wasEnabled = true
            elseif wasEnabled then
                restoreAllPrompts()
                wasEnabled = false
            end

            task.wait(0.5)
        end
    end)

    _G.LootRuntime.InstantInteractThread = thread
    table.insert(_G.LootConnections, thread)
end

function InstantInteract:Init(UIRef)
    setupPromptListener()
    setupStateLoop()

    if isEnabled() then
        patchVisiblePrompts()
    end

    log("Initialized.")
end

return InstantInteract
