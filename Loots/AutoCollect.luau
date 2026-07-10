--[[
    ========================================================================
    Loots - Auto Collect
    ========================================================================
    Collects Cash and Valuables from the active Nightbound loot table.

    The Nightbound client stores the current loot table from
    Events.Loot.LootObject.OnClientEvent, then collects currency through:
        Events.Loot.LootObject:FireServer(lootTable, "Cash")
        Events.Loot.LootObject:FireServer(lootTable, "Valuables")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local AutoCollect = {}
AutoCollect.Name = "Auto Collect Loot"
AutoCollect.Description = "Automatically collects Cash and Valuables using Legit, Blatant, or Instant mode."

local MAX_LOOT_DISTANCE = 10.5
local LEGIT_COLLECT_DELAY = 0.42
local BLATANT_COLLECT_DELAY = 0.06
local INSTANT_IDLE_DELAY = 0.12
local INSTANT_RETRY_COUNT = 2
local IDLE_DELAY = 0.35
local RESCAN_INTERVAL = 1.25

local function log(message)
    print("[Loots - AutoCollect] " .. tostring(message))
end

local function getNumericAttribute(instance, attributeName)
    if not instance then
        return 0
    end

    local value = instance:GetAttribute(attributeName)
    if type(value) == "number" then
        return value
    end

    return tonumber(value) or 0
end

local function getLootRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    local loot = events and events:FindFirstChild("Loot")
    return loot and loot:FindFirstChild("LootObject")
end

local function getRoot()
    local character = LocalPlayer.Character
    return character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character.PrimaryPart)
end

local function getLootBasePosition(lootTable)
    if not lootTable then
        return nil
    end

    local parent = lootTable.Parent
    if parent and parent:IsA("BasePart") then
        return parent.Position
    end

    if parent and parent:IsA("Model") then
        local part = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position
    end

    if lootTable:IsA("BasePart") then
        return lootTable.Position
    end

    return nil
end

local function isLootTableInRange(lootTable)
    local root = getRoot()
    local position = getLootBasePosition(lootTable)

    if not root or not position then
        return false
    end

    return (root.Position - position).Magnitude <= MAX_LOOT_DISTANCE
end

local function lootHasSelectedCurrency(lootTable)
    if not _G.LootStates or type(_G.LootStates.CollectLootOptions) ~= "table" then
        return false
    end

    local options = _G.LootStates.CollectLootOptions

    if options.Cash and getNumericAttribute(lootTable, "Cash") > 0 then
        return true
    end

    if options.Valuables and getNumericAttribute(lootTable, "Valuables") > 0 then
        return true
    end

    return false
end

local function isUsableLootTable(instance)
    return instance
        and instance.Parent
        and instance:GetAttribute("LootName") ~= nil
        and (instance:GetAttribute("Cash") ~= nil or instance:GetAttribute("Valuables") ~= nil)
        and lootHasSelectedCurrency(instance)
        and isLootTableInRange(instance)
end

local function rememberActiveLoot(lootTable, lootContext)
    _G.LootRuntime = _G.LootRuntime or {}

    if lootTable and lootTable.Parent then
        _G.LootRuntime.ActiveLootObject = lootTable
        _G.LootRuntime.ActiveLootContext = lootContext or lootTable.Parent
    end
end

local function findNearbyLootTable()
    _G.LootRuntime = _G.LootRuntime or {}

    local now = os.clock()
    if _G.LootRuntime.LastLootScanAt and now - _G.LootRuntime.LastLootScanAt < RESCAN_INTERVAL then
        return _G.LootRuntime.NearbyLootObject
    end

    _G.LootRuntime.LastLootScanAt = now
    _G.LootRuntime.NearbyLootObject = nil

    local map = Workspace:FindFirstChild("Map")
    local lootRoot = map and map:FindFirstChild("Loot")
    if not lootRoot then
        return nil
    end

    local bestLoot = nil
    local bestDistance = math.huge
    local root = getRoot()
    if not root then
        return nil
    end

    for _, descendant in ipairs(lootRoot:GetDescendants()) do
        if descendant.Name == "LootTable" and descendant:GetAttribute("LootName") ~= nil then
            local position = getLootBasePosition(descendant)
            local distance = position and (root.Position - position).Magnitude or math.huge
            if distance < bestDistance and distance <= MAX_LOOT_DISTANCE and lootHasSelectedCurrency(descendant) then
                bestLoot = descendant
                bestDistance = distance
            end
        end
    end

    _G.LootRuntime.NearbyLootObject = bestLoot
    return bestLoot
end

local function getCurrentLootTable()
    _G.LootRuntime = _G.LootRuntime or {}

    local activeLoot = _G.LootRuntime.ActiveLootObject
    if isUsableLootTable(activeLoot) then
        return activeLoot
    end

    _G.LootRuntime.ActiveLootObject = nil

    if _G.LootStates and (_G.LootStates.CollectMode == "Blatant" or _G.LootStates.CollectMode == "Instant") then
        local nearbyLoot = findNearbyLootTable()
        if isUsableLootTable(nearbyLoot) then
            return nearbyLoot
        end
    end

    return nil
end

local function getSelectedCurrencyOrder()
    local options = _G.LootStates and _G.LootStates.CollectLootOptions
    if type(options) ~= "table" then
        return {}
    end

    local order = {}

    if options.Cash then
        table.insert(order, "Cash")
    end

    if options.Valuables then
        table.insert(order, "Valuables")
    end

    return order
end

local function collectCurrency(lootTable, currencyName)
    local remote = getLootRemote()
    if not remote or not lootTable then
        return false
    end

    if getNumericAttribute(lootTable, currencyName) <= 0 then
        return false
    end

    local ok = pcall(function()
        remote:FireServer(lootTable, currencyName)
    end)

    return ok
end

local function collectOnce()
    local lootTable = getCurrentLootTable()
    if not lootTable then
        return false
    end

    local mode = (_G.LootStates and _G.LootStates.CollectMode) or "Legit"
    local didCollect = false
    local selectedCurrencies = getSelectedCurrencyOrder()

    if mode == "Instant" then
        for _ = 1, INSTANT_RETRY_COUNT do
            for _, currencyName in ipairs(selectedCurrencies) do
                didCollect = collectCurrency(lootTable, currencyName) or didCollect
            end
        end

        return didCollect
    end

    for _, currencyName in ipairs(selectedCurrencies) do
        if collectCurrency(lootTable, currencyName) then
            didCollect = true
            if mode == "Blatant" then
                task.wait(BLATANT_COLLECT_DELAY)
            else
                task.wait(LEGIT_COLLECT_DELAY + math.random(5, 20) / 100)
            end
        end
    end

    return didCollect
end

local function setupLootListener()
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}

    if _G.LootRuntime.AutoCollectLootConnection and _G.LootRuntime.AutoCollectLootConnection.Connected then
        return
    end

    local remote = getLootRemote()
    if not remote then
        warn("[Loots - AutoCollect] Events.Loot.LootObject not found.")
        return
    end

    local connection = remote.OnClientEvent:Connect(function(lootTable, lootContext)
        rememberActiveLoot(lootTable, lootContext)
        if _G.LootStates and _G.LootStates.AutoCollectLoot then
            task.defer(collectOnce)
        end
    end)

    _G.LootRuntime.AutoCollectLootConnection = connection
    table.insert(_G.LootConnections, connection)
end

local function setupCollectLoop()
    _G.LootConnections = _G.LootConnections or {}
    _G.LootRuntime = _G.LootRuntime or {}

    if _G.LootRuntime.AutoCollectThread and coroutine.status(_G.LootRuntime.AutoCollectThread) ~= "dead" then
        return
    end

    local thread = task.spawn(function()
        while _G.LootStates do
            local enabled = _G.LootStates.AutoCollectLoot == true

            if enabled then
                local didCollect = collectOnce()
                local mode = _G.LootStates.CollectMode
                if mode == "Instant" then
                    task.wait(didCollect and 0.05 or INSTANT_IDLE_DELAY)
                elseif didCollect then
                    task.wait(mode == "Blatant" and BLATANT_COLLECT_DELAY or LEGIT_COLLECT_DELAY)
                else
                    task.wait(IDLE_DELAY)
                end
            else
                task.wait(IDLE_DELAY)
            end
        end
    end)

    _G.LootRuntime.AutoCollectThread = thread
    table.insert(_G.LootConnections, thread)
end

function AutoCollect:Init(UIRef)
    setupLootListener()
    setupCollectLoop()
    log("Initialized.")
end

return AutoCollect
