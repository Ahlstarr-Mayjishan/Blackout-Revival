--[[
    ========================================================================
    Player Modifier - NoFallDamage Module (Fall Damage Immunity Descriptor)
    ========================================================================
    This module acts as a registration handle for No Fall Damage.
    Its execution logic is handled by the global hook in Executor.luau.
]]

local NoFallDamage = {}
NoFallDamage.Name = "No Fall Damage Logic"
NoFallDamage.Description = "Implements fall damage immunity via RemoteEvent hooks."

function NoFallDamage:Init(UIRef)
    print("[Player Modifier - NoFallDamage] Registered with global hooking engine.")
end

return NoFallDamage
