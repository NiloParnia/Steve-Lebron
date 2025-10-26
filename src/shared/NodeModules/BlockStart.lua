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

local BlockStart = NodeFactory.Create{
    Name        = "BlockStart",
    Keybind     = Enum.KeyCode.Unknown,
    Cooldown    = 0,
    Radius      = 0.1,
    Damage      = 0,
    GuardDamage = 0,
    Stun        = 0,
}

if NL and NL.BlockStart then
    BlockStart.OnStart = function(player, ...)
        local tags = { Defensive = true, Block = true }
        NodeSense.Emit(player, "Block", tags, { nodeName = "Block" })
        return NL.BlockStart(player, ...)
    end
end

return BlockStart