--------------------------------------------------------------------
-- NodeFactory • v8.3 (mount-safe)
-- + Execute(rootPart, extra) signature
-- + GetCFrame(extra) & LinkedParts(extra)
-- + Blocks node execution while player is Mounted (Humanoid attribute)
--   (per-node override: cfg.AllowWhileMounted = true)
--------------------------------------------------------------------
local RS       = game:GetService("ReplicatedStorage")
local Players  = game:GetService("Players")

-- dependencies
local HitboxService      = require(RS:WaitForChild("HitboxService"))
local CooldownService    = require(RS:WaitForChild("CooldownService"))
local SpeedController    = require(RS:WaitForChild("SpeedController"))
local IFrameStore        = require(RS:WaitForChild("IFrameStore"))
local AttackStateService = require(RS:WaitForChild("AttackStateService"))
local DamageService      = require(RS:WaitForChild("DamageService"))
local GuardService       = require(RS:WaitForChild("GuardService"))
local StunService        = require(RS:WaitForChild("StunService"))
local KnockbackService   = require(RS:WaitForChild("KnockbackService"))

local NodeFactory = {}

--------------------------------------------------------------------
-- Mount helpers (future-proof)
--------------------------------------------------------------------
local MOUNT_DEBUG = false

local function isMountedPlayer(player: Player?): boolean
	if not player then return false end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum:GetAttribute("Mounted") == true
end

local function playerFromRoot(rootPart: BasePart?)
	if not rootPart then return nil, nil end
	local char = rootPart.Parent
	if not char then return nil, nil end
	return Players:GetPlayerFromCharacter(char), char
end

--------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------
function NodeFactory.Create(cfg)
	assert(cfg and type(cfg) == "table", "NodeFactory: cfg table required")
	assert(cfg.Name, "NodeFactory: Name required")
	assert(cfg.Radius or cfg.UseMovingHitbox, "NodeFactory: Radius required")

	local node = {}
	for k, v in pairs(cfg) do node[k] = v end

	-- Optional per-node escape hatch:
	-- cfg.AllowWhileMounted = true  -- e.g., emotes you want to permit

	function node:Execute(rootPart, extra)
		if not rootPart or typeof(rootPart) ~= "Instance" then return end

		-- Resolve caller
		local player, char = playerFromRoot(rootPart)
		-- 🚧 Hard gate while mounted (unless explicitly allowed on this node)
		if player and (not self.AllowWhileMounted) and isMountedPlayer(player) then
			if MOUNT_DEBUG then
				print(("[NodeFactory] BLOCKED while mounted ▶ %s  node=%s")
					:format(player.Name, tostring(self.Name or "?")))
			end
			return
		end

		-- Cooldown (only if configured; Revolver handles its own)
		if player and self.Cooldown and self.Cooldown > 0 then
			if not CooldownService.CanUse(player, self.Name) then return end
			CooldownService.Apply(player, self.Name, self.Cooldown)
		end

		-- Self-effects / attack state
		if player and self.Speed then
			SpeedController.Apply(player, self.Speed, self.SpeedDuration or 0.5)
		end
		AttackStateService.Start(char, {
			duration   = self.Lifetime or 0.2,
			hyperArmor = self.HyperArmor,
			iFrames    = self.IFrames
		})

		-- Animation (only if set in cfg)
		if self.AnimationId then
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				local anim = Instance.new("Animation")
				anim.AnimationId = self.AnimationId
				hum:LoadAnimation(anim):Play()
			end
		end

		-- Hitbox params
		local lifetime     = self.Lifetime or 0.2
		local oneShot      = (self.OneShot ~= false)
		local destroyOnHit = (self.DestroyOnHit or oneShot)

		local linkedParts = {}
		if type(self.LinkedParts) == "function" then
			linkedParts = self.LinkedParts(extra)
		elseif type(self.LinkedParts) == "table" then
			linkedParts = self.LinkedParts
		end

		local ignoreList = {}
		if char then table.insert(ignoreList, char) end
		if typeof(extra) == "Instance" then
			table.insert(ignoreList, extra) -- ignore the projectile itself
		end
		if self.IgnoreList then
			for _, inst in ipairs(self.IgnoreList) do table.insert(ignoreList, inst) end
		end

		-- On-hit, we re-check “mounted” (covers long-running hitboxes if rider mounts mid-flight)
		local function onHit(targetChar: Model)
			if player and (not node.AllowWhileMounted) and isMountedPlayer(player) then
				if MOUNT_DEBUG then
					print(("[NodeFactory] onHit blocked (now mounted) ▶ %s  node=%s")
						:format(player.Name, tostring(node.Name or "?")))
				end
				return
			end

			local dmg =
				(typeof(node.Damage) == "number" and { hp = node.Damage, guard = node.GuardDamage or 0, parryable = (node.Parryable ~= false) })
				or (typeof(node.Damage) == "table" and node.Damage)
				or { guard = node.GuardDamage or 0, parryable = (node.Parryable ~= false) }

			DamageService.DealDamage(targetChar, dmg, char)

			if node.Stun and node.Stun > 0 then
				StunService.Apply(targetChar, node.Stun)
			end

			if node.KnockbackForce and node.KnockbackForce > 0 then
				local tr = targetChar:FindFirstChild("HumanoidRootPart")
				if tr and rootPart then
					local dir = (tr.Position - rootPart.Position)
					KnockbackService.Apply(targetChar, dir, node.KnockbackForce, node.KnockbackDur)
				end
			end
		end

		-- Spawn hitbox
		if self.UseMovingHitbox then
			assert(type(self.GetCFrame) == "function", "NodeFactory: GetCFrame(extra) required for moving hitbox")
			HitboxService.CreateMoving(
				function() return self.GetCFrame(extra) end,
				self.Radius, lifetime, ignoreList, oneShot, onHit,
				{ destroyOnHit = destroyOnHit, linkedParts = linkedParts, moving = true }
			)
		else
			HitboxService.Create(
				rootPart.CFrame, self.Radius, lifetime, ignoreList, oneShot, onHit,
				{ destroyOnHit = destroyOnHit, linkedParts = linkedParts }
			)
		end
	end

	return node
end

return NodeFactory
