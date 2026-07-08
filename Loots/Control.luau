--[[
    ========================================================================
    Loots - Control Module
    ========================================================================
    Administrative controls for the Loots suite.
]]

local Control = {}
Control.Name = "Loots Control"
Control.Description = "Controls and cleanup actions for loot automation."

function Control:Init(UIRef)
    UIRef:CreateSection("Loots Options")

    UIRef:CreateButton({
        Name = "Unload Loots",
        Callback = function()
            local gcModule = nil

            pcall(function()
                if type(readfile) == "function" and type(isfile) == "function" and isfile("Loots/GC.luau") then
                    gcModule = loadstring(readfile("Loots/GC.luau"))()
                end
            end)

            if gcModule and type(gcModule.cleanup) == "function" then
                gcModule.cleanup()
            end
        end,
    })

    print("[Loots - Control] Initialized.")
end

return Control
