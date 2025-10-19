-- Canonical telemetry facts for the cardinal moves.
-- Used by NodeFactory stubs (intent) and can also be used by NodeLibrary.
local Facts = {}

Facts.Punch = {
	Name         = "Punch",
	-- Balance: your current M1s
	Damage       = 3.3,
	GuardDamage  = 0,
	Chip         = 0,
	Stun         = 0.20,    -- micro stagger on clean hit (AI weight only)
	Blockable    = true,
	Parryable    = false,
	Melee        = true,
	M1           = true,
	Radius       = 5,
}

Facts.Heavy = {
	Name         = "Heavy",
	Damage       = 7.0,
	GuardDamage  = 30,
	Chip         = 2.0,
	Stun         = 0.40,    -- mild stagger on hit (AI weight only)
	Blockable    = false,
	Parryable    = true,
	Melee        = true,
	Heavy        = true,
	Radius       = 7,
	KnockbackForce = 90,
	KnockbackDur   = 0.35,
}

Facts.Block = { Name = "Block" }
Facts.Dodge = { Name = "Dodge" }

return Facts
