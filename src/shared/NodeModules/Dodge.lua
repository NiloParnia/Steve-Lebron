local RS          = game:GetService("ReplicatedStorage")
local NodeFactory = require(game.ReplicatedStorage.NodeFactory)
local NodeSense   = require(RS:WaitForChild("NodeSense"))

local NL = require(game.ServerScriptService:FindFirstChild("NodeLibrary")
	or RS:FindFirstChild("NodeLibrary"))

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
		-- Intent ping so AI recognizes an incoming evade/i-frame action.
		local tags = NodeSense.CollectTags(Dodge, {
			Defensive = true,
			Dodge     = true,
			IFrame    = true,
			Evade     = true,
		})

		NodeSense.Emit(player, "Dodge", tags, {
			nodeName = "Dodge",
			-- duration can be inferred later from IFrameStore if needed
		})

		return NL.Dodge(player, ...)
	end
end

return Dodge
