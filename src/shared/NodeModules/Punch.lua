local RS          = game:GetService("ReplicatedStorage")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))
local NodeSense   = require(RS:WaitForChild("NodeSense"))
local Facts       = require(RS:WaitForChild("CardinalFacts"))

local NL
do
	local s = (game.ServerScriptService:FindFirstChild("NodeLibrary") or RS:FindFirstChild("NodeLibrary"))
	if s then NL = require(s) end
end

local Punch = NodeFactory.Create{
	Name   = "Punch",
	Radius = 0.1,          -- satisfy NodeFactory assert; not used for telemetry
}

if NL and NL.Punch then
	Punch.OnStart = function(actor, ...)
		local f = Facts.Punch
		NodeSense.EmitWithDef(actor, f, { Attack = true }, {
			nodeName    = "Punch",
			damage      = f.Damage,
			guardDamage = f.GuardDamage,
			stun        = f.Stun,
		})
		return NL.Punch(actor, ...)
	end
end

return Punch
