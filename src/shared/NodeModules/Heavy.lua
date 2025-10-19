local RS          = game:GetService("ReplicatedStorage")
local NodeFactory = require(RS:WaitForChild("NodeFactory"))
local NodeSense   = require(RS:WaitForChild("NodeSense"))
local Facts       = require(RS:WaitForChild("CardinalFacts"))

local NL
do
	local s = (game.ServerScriptService:FindFirstChild("NodeLibrary") or RS:FindFirstChild("NodeLibrary"))
	if s then NL = require(s) end
end

local Heavy = NodeFactory.Create{
	Name   = "Heavy",
	Radius = 0.1,          -- satisfy NodeFactory assert; not used for telemetry
}

if NL and NL.Heavy then
	Heavy.OnStart = function(actor, ...)
		local f = Facts.Heavy
		NodeSense.EmitWithDef(actor, f, { Attack = true }, {
			nodeName    = "Heavy",
			damage      = f.Damage,
			guardDamage = f.GuardDamage,
			stun        = f.Stun,
			kbForce     = f.KnockbackForce,
		})
		return NL.Heavy(actor, ...)
	end
end

return Heavy
