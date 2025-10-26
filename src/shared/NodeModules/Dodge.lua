local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))
local NodeSense = require(RS:WaitForChild("NodeSense"))

-- Server-only NodeLibrary
local NL
if RunService:IsServer() then
    local SSS = game:GetService("ServerScriptService")
    NL = require(SSS:WaitForChild("NodeLibrary"))
else
    NL = setmetatable({}, { __index = function() return function() end end })
end

local Dodge = NodeFactory.Create{
    Name        = "Dodge",
    Keybind     = Enum.KeyCode.Unknown,
    Cooldown    = 0,
    Radius      = 0.1,
    Damage      = 0,
    GuardDamage = 0,
    Stun        = 0,
}

if NL and NL.Dodge then
    Dodge.OnStart = function(player, ...)
        local tags = { Defensive = true, Dodge = true }
        NodeSense.Emit(player, "Dodge", tags, { nodeName = "Dodge" })
        return NL.Dodge(player, ...)
    end
end

return Dodge