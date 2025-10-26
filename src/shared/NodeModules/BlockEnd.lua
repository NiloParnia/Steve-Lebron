local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))

-- Server-only NodeLibrary
local NL
if RunService:IsServer() then
    local SSS = game:GetService("ServerScriptService")
    NL = require(SSS:WaitForChild("NodeLibrary"))
else
    NL = setmetatable({}, { __index = function() return function() end end })
end

local BlockEnd = NodeFactory.Create{
    Name        = "BlockEnd",
    Keybind     = Enum.KeyCode.Unknown,
    Cooldown    = 0,
    Radius      = 0.1,
    Damage      = 0,
    GuardDamage = 0,
    Stun        = 0,
}

if NL and NL.BlockEnd then
    BlockEnd.OnStart = function(player, ...)
        -- GuardService.EndBlock will emit "BlockEnd" via NodeSense; no UI emit needed here.
        return NL.BlockEnd(player, ...)
    end
end

return BlockEnd