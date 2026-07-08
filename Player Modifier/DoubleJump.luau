--[[
    ========================================================================
    Player Modifier - DoubleJump Module (Infinite Double Jump Logic)
    ========================================================================
    This module contains the background execution logic for Infinite Double Jump.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local DoubleJump = {}
DoubleJump.Name = "Infinite Double Jump Logic"
DoubleJump.Description = "Handles mid-air jumping physics and notifications."

function DoubleJump:Init(UIRef)
    _G.ModifierRuntime = _G.ModifierRuntime or {}

    local doubleJumpRemote = ReplicatedStorage:WaitForChild("Events", 5) and ReplicatedStorage.Events:WaitForChild("Player", 5) and ReplicatedStorage.Events.Player:WaitForChild("GearAbility", 5)

    if not _G.ModifierRuntime.DoubleJumpStateThread
        or coroutine.status(_G.ModifierRuntime.DoubleJumpStateThread) == "dead" then
        local stateThread = task.spawn(function()
            while _G.ModifierStates do
                if _G.ModifierStates.DoubleJump and _G.CharacterStates then
                    _G.CharacterStates.DoubleJump = true
                    _G.CharacterStates.DoubleJumpCD = false
                end

                local delayTime = 0.08
                if _G.PerformanceGuard and type(_G.PerformanceGuard.GetDelay) == "function" then
                    delayTime = _G.PerformanceGuard.GetDelay(delayTime, "light")
                end

                task.wait(delayTime)
            end
        end)

        _G.ModifierRuntime.DoubleJumpStateThread = stateThread
        if _G.ModifierConnections then
            table.insert(_G.ModifierConnections, stateThread)
        end
    end
    
    if _G.ModifierRuntime.DoubleJumpInputConnection and _G.ModifierRuntime.DoubleJumpInputConnection.Connected then
        print("[Player Modifier - DoubleJump] Double Jump event handler already connected.")
        return
    end

    -- Setup the JumpRequest connection
    local connection = UserInputService.JumpRequest:Connect(function()
        if not _G.ModifierStates or not _G.ModifierStates.DoubleJump then
            return
        end
        
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        
        if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
            if _G.CharacterStates then
                _G.CharacterStates.DoubleJump = true
                _G.CharacterStates.DoubleJumpCD = false
                _G.CharacterStates.Parkour = false
            end
            
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            
            -- Notify server of the jump
            if doubleJumpRemote then
                doubleJumpRemote:FireServer("DoubleJump")
            end
            
            -- Play sound locally
            local boosterSound = character:FindFirstChild("PrimaryPart") and character.PrimaryPart:FindFirstChild("Booster")
            if boosterSound then
                boosterSound:Play()
            end
        end
    end)
    
    -- Register connection for GC cleanup
    _G.ModifierRuntime.DoubleJumpInputConnection = connection
    if _G.ModifierConnections then
        table.insert(_G.ModifierConnections, connection)
    end
    
    print("[Player Modifier - DoubleJump] Double Jump event handler connected.")
end

return DoubleJump
