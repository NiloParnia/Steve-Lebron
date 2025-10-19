local RS          = game:GetService("ReplicatedStorage")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))
local NodeSense   = require(RS:WaitForChild("NodeSense"))

local NL = require(game.ServerScriptService:FindFirstChild("NodeLibrary")
	or RS:FindFirstChild("NodeLibrary"))

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
		-- Intent ping so AI sets targetBlocking immediately.
		local tags = NodeSense.CollectTags(BlockStart, {
			Defensive = true,
			Block     = true,
		})
		NodeSense.Emit(player, "Block", tags, {
			nodeName = "Block",
		})

		return NL.BlockStart(player, ...)
	end
end

return BlockStart
