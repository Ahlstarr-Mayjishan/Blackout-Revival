--[[
    ========================================================================
    Player Modifier - Performance Guard
    ========================================================================
    Central load controller for long-running executor modules.

    Goals:
    - Prevent duplicate worker threads after UI reloads.
    - Reduce scan/update frequency when frame time gets bad.
    - Periodically trim dead cleanup entries and step Lua GC.
]]

local RunService = game:GetService("RunService")

local PerformanceGuard = {}
PerformanceGuard.Name = "Performance Guard"
PerformanceGuard.Description = "Continuously reduces module load when the client starts lagging."

local SAMPLE_ALPHA = 0.08
local HOUSEKEEPING_INTERVAL = 2.0
local FULL_GC_INTERVAL = 30.0

local state = _G.PerformanceGuardState or {
    AvgDt = 1 / 60,
    Level = 0,
    StartedAt = os.clock(),
    LastHousekeeping = 0,
    LastFullGc = 0,
    NextRunAt = {},
    LastLogAt = 0,
}

_G.PerformanceGuardState = state

local function log(message)
    print("[PerformanceGuard] " .. tostring(message))
end

local function isConnectionAlive(item)
    if typeof(item) == "RBXScriptConnection" then
        return item.Connected
    end

    if typeof(item) == "thread" then
        return coroutine.status(item) ~= "dead"
    end

    if type(item) == "table" then
        return true
    end

    return false
end

local function compactList(list)
    if type(list) ~= "table" then
        return 0, 0
    end

    local originalCount = #list
    local writeIndex = 1

    for readIndex = 1, originalCount do
        local item = list[readIndex]
        if isConnectionAlive(item) then
            list[writeIndex] = item
            writeIndex += 1
        end
    end

    for index = writeIndex, originalCount do
        list[index] = nil
    end

    return originalCount, writeIndex - 1
end

local function getConnectionPressure()
    local modifierCount = type(_G.ModifierConnections) == "table" and #_G.ModifierConnections or 0
    local aimCount = type(_G.AimAssistConnections) == "table" and #_G.AimAssistConnections or 0
    return modifierCount + aimCount
end

local function updateLoadLevel()
    local fps = 1 / math.max(state.AvgDt, 1 / 240)
    local connections = getConnectionPressure()
    local level = 0

    if fps < 50 or connections > 45 then
        level = 1
    end

    if fps < 38 or connections > 75 then
        level = 2
    end

    if fps < 28 or connections > 110 then
        level = 3
    end

    state.Level = level
    return level, fps, connections
end

local function getDelay(baseDelay, weight)
    local level = state.Level or 0
    local multiplier = 1

    if level == 1 then
        multiplier = weight == "heavy" and 1.8 or 1.35
    elseif level == 2 then
        multiplier = weight == "heavy" and 3.0 or 2.0
    elseif level >= 3 then
        multiplier = weight == "heavy" and 5.0 or 3.0
    end

    return math.max(baseDelay * multiplier, baseDelay)
end

local function shouldRun(key, baseInterval, weight)
    local now = os.clock()
    local nextRunAt = state.NextRunAt[key]

    if nextRunAt and now < nextRunAt then
        return false
    end

    state.NextRunAt[key] = now + getDelay(baseInterval, weight)
    return true
end

local function stepGc(forceFull)
    pcall(function()
        if forceFull then
            collectgarbage("collect")
        else
            collectgarbage("step", 80)
        end
    end)
end

local function housekeeping()
    local beforeModifier, afterModifier = compactList(_G.ModifierConnections)
    local beforeAim, afterAim = compactList(_G.AimAssistConnections)

    stepGc(false)

    local now = os.clock()
    if now - state.LastFullGc >= FULL_GC_INTERVAL then
        state.LastFullGc = now
        stepGc(true)
    end

    local removed = (beforeModifier - afterModifier) + (beforeAim - afterAim)
    local level, fps, connections = updateLoadLevel()

    if removed > 0 or level >= 2 then
        if now - state.LastLogAt >= 5 then
            state.LastLogAt = now
            log(string.format("level=%d fps=%.0f connections=%d removed=%d", level, fps, connections, removed))
        end
    end
end

function PerformanceGuard.GetLevel()
    return state.Level or 0
end

function PerformanceGuard.GetDelay(baseDelay, weight)
    return getDelay(baseDelay, weight)
end

function PerformanceGuard.ShouldRun(key, baseInterval, weight)
    return shouldRun(key, baseInterval, weight)
end

function PerformanceGuard.GetStats()
    local _, fps, connections = updateLoadLevel()
    return {
        Level = state.Level,
        FPS = fps,
        Connections = connections,
        Uptime = os.clock() - state.StartedAt,
    }
end

function PerformanceGuard.Cleanup()
    if state.HeartbeatConnection and state.HeartbeatConnection.Connected then
        state.HeartbeatConnection:Disconnect()
    end

    state.HeartbeatConnection = nil
    state.NextRunAt = {}
end

function PerformanceGuard:Init(UIRef)
    _G.ModifierConnections = _G.ModifierConnections or {}
    _G.ModifierRuntime = _G.ModifierRuntime or {}

    _G.PerformanceGuard = PerformanceGuard

    if state.HeartbeatConnection and state.HeartbeatConnection.Connected then
        log("Already running.")
        return
    end

    state.HeartbeatConnection = RunService.Heartbeat:Connect(function(dt)
        state.AvgDt = state.AvgDt + (dt - state.AvgDt) * SAMPLE_ALPHA

        local now = os.clock()
        if now - state.LastHousekeeping >= HOUSEKEEPING_INTERVAL then
            state.LastHousekeeping = now
            housekeeping()
        end
    end)

    table.insert(_G.ModifierConnections, state.HeartbeatConnection)
    table.insert(_G.ModifierConnections, {
        Destroy = function()
            PerformanceGuard.Cleanup()
        end,
    })

    pcall(function()
        UIRef:CreateSection("Performance")
        UIRef:CreateButton({
            Name = "Print Performance Guard Stats",
            Callback = function()
                local stats = PerformanceGuard.GetStats()
                log(string.format(
                    "level=%d fps=%.0f connections=%d uptime=%.0fs",
                    stats.Level,
                    stats.FPS,
                    stats.Connections,
                    stats.Uptime
                ))
            end,
        })
    end)

    log("Started.")
end

return PerformanceGuard
