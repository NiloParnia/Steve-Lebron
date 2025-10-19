local RS          = game:GetService("ReplicatedStorage")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))

local NL = require(game.ServerScriptService:FindFirstChild("NodeLibrary")
	or RS:FindFirstChild("NodeLibrary"))

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
		-- No NodeSense intent here: GuardService.EndBlock will emit "BlockEnd".
		return NL.BlockEnd(player, ...)
	end
end

return BlockEnd
