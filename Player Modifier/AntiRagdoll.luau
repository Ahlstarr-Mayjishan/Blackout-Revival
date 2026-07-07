--[[
    ========================================================================
    Player Modifier - AntiRagdoll Module (Anti-Ragdoll Descriptor)
    ========================================================================
    This module acts as a registration handle for Anti-Ragdoll.
    Its execution logic is handled by the global hook in Executor.luau.
]]

local AntiRagdoll = {}
AntiRagdoll.Name = "Anti-Ragdoll Logic"
AntiRagdoll.Description = "Implements ragdoll protection via RemoteEvent hooks."

function AntiRagdoll:Init(UIRef)
    print("[Player Modifier - AntiRagdoll] Registered with global hooking engine.")
end

return AntiRagdoll
