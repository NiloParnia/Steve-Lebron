-- ReplicatedStorage/EnemySpecs.lua
-- enemyId → spec: which brain, look, defaults, difficulty (DEF/OFF), etc.
return {
	-- Worst-tier tutorial enemy (dopey)
	Rounder_Tutorial = {
		enemyType   = "Rounder",
		
		leashRadius = 30,
		aiProfile   = "RounderV1",
		stats       = { WalkSpeed = 14, JumpPower = 40 },
		DEF         = 100,   -- near-worst defense/reactivity
		OFF         = 1,   -- near-worst aggression/pressure
	},

}
