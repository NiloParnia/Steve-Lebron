--------------------------------------------------------------------
-- HitboxService (v1.7) — contact-only, outcome via DamageService
-- - Legacy path: you can still pass a `callback(mdl)` → unchanged
-- - New path: pass opts.damage / opts.attacker and it will call
--             DamageService.DealDamage(defender, opts.damage, opts.attacker)
-- - Optional: opts.intent=true → one-time NodeSense "intent" emit at spawn
--------------------------------------------------------------------
local HitboxService = {}

local Debris   = game:GetService("Debris")
local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")

local DamageService = require(RS:WaitForChild("DamageService"))
local NodeSense     = require(RS:WaitForChild("NodeSense"))

-- Utility: return Model with living Humanoid
local function getLivingCharacter(inst)
	local mdl = inst:FindFirstAncestorOfClass("Model")
	if not mdl then return nil end
	local hum = mdl:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return mdl
	end
end

-- Defender entity: prefer Player if one owns the model
local function toDefenderEntity(mdl)
	local plr = Players:GetPlayerFromCharacter(mdl)
	return plr or mdl
end

-- Spawn invisible anchored sphere
local function makeSphere(radius, cf)
	local p = Instance.new("Part")
	p.Shape        = Enum.PartType.Ball
	p.Size         = Vector3.new(1,1,1) * (radius*2)
	p.Transparency = 1
	p.CanCollide   = false
	p.Anchored     = true
	p.CFrame       = cf
	p.Name         = "HitboxSphere"
	p.Parent       = workspace
	return p
end

-- Internal create function
local function _create(getCF, radius, lifetime, ignoreList, oneShot, callback, opts)
	lifetime   = lifetime   or 0.2
	oneShot    = (oneShot    ~= false)
	ignoreList = ignoreList or {}
	opts       = opts       or {}

	-- ignore any descendants of these instances
	local function isIgnored(inst)
		for _,ign in ipairs(ignoreList) do
			if inst == ign or inst:IsDescendantOf(ign) then
				return true
			end
		end
		return false
	end

	local destroyOnHit = opts.destroyOnHit
	if destroyOnHit == nil then destroyOnHit = oneShot end

	local linkedParts  = opts.linkedParts or {}

	-- Optional: one-time "intent" telemetry on arm
	if opts.intent == true then
		local nodeName = opts.nodeName
			or (typeof(opts.damage)=="table" and (opts.damage.nodeName or opts.damage.NodeName))
			or "Hitbox"
		local tags = nil
		if typeof(NodeSense) == "table" and typeof(NodeSense.CollectTags) == "function" then
			local dmgTbl = (typeof(opts.damage)=="table") and opts.damage or {}
			tags = NodeSense.CollectTags(dmgTbl, opts.tagsOverride)
		end
		pcall(function()
			NodeSense.Emit(opts.attacker, nodeName, tags, { armed = true })
		end)
	end

	local sphere = makeSphere(radius, getCF())
	print("[HitboxService] 🔵 spawned at", sphere.CFrame.Position)

	-- Optional per-target throttle for moving hitboxes
	local perTargetCooldown = tonumber(opts.hitCooldown)
	local recentHits = {} -- [Model] = expireTick

	local running = true
	local conn
	conn = sphere.Touched:Connect(function(other)
		if not running then return end

		if isIgnored(other) then
			print("[HitboxService]   ⚪ ignored collision with", other:GetFullName())
			return
		end

		local mdl = getLivingCharacter(other)
		if not mdl then
			print("[HitboxService]   ⚪ non-target hit with", other:GetFullName())
			return
		end

		-- Per-target throttle (optional)
		if perTargetCooldown and perTargetCooldown > 0 then
			local now = tick()
			if (recentHits[mdl] or 0) > now then
				-- still cooling down for this target
				return
			end
			recentHits[mdl] = now + perTargetCooldown
		end

		print("[HitboxService]   🔴 hit target:", mdl.Name)

		-- Legacy path: explicit callback takes priority
		if typeof(callback) == "function" then
			pcall(callback, mdl)
		else
			-- New sugar path: auto route to DamageService if damage is provided
			local dmg = opts.damage
			if dmg ~= nil then
				-- ensure nodeName present if provided separately
				if typeof(dmg) == "table" then
					if dmg.nodeName == nil and dmg.NodeName == nil and opts.nodeName then
						-- shallow clone to avoid mutating caller table
						local clone = {}
						for k,v in pairs(dmg) do clone[k]=v end
						clone.nodeName = opts.nodeName
						dmg = clone
					end
				end

				local defender = toDefenderEntity(mdl)
				pcall(function()
					DamageService.DealDamage(defender, dmg, opts.attacker)
				end)
			end
		end

		if destroyOnHit then
			running = false
			print("[HitboxService]   🗑 destroyOnHit cleanup")
			conn:Disconnect()
			if sphere.Parent then sphere:Destroy() end
			for _,p in ipairs(linkedParts) do
				if p and p.Destroy then
					print("[HitboxService]     🗑 linkedPart destroyed:", p.Name or p.ClassName)
					p:Destroy()
				end
			end
		end
	end)

	if opts.moving then
		task.spawn(function()
			local t0 = tick()
			while running and tick() - t0 < lifetime do
				sphere.CFrame = getCF()
				task.wait()
			end
			if running then
				running = false
				print("[HitboxService] ⏳ lifetime expired, cleanup")
				conn:Disconnect()
				if sphere.Parent then sphere:Destroy() end
			end
		end)
	else
		Debris:AddItem(sphere, lifetime)
	end
end

-- Stationary hitbox
function HitboxService.Create(originCF, radius, lifetime, ignoreList, oneShot, callback, opts)
	opts = opts or {}
	opts.moving = false
	_create(function() return originCF end,
		radius, lifetime, ignoreList, oneShot, callback, opts)
end

-- Moving hitbox
function HitboxService.CreateMoving(getCFrame, radius, lifetime, ignoreList, oneShot, callback, opts)
	opts = opts or {}
	opts.moving = true
	_create(getCFrame, radius, lifetime, ignoreList, oneShot, callback, opts)
end

return HitboxService
