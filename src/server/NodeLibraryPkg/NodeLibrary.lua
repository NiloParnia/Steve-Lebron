local NodeLibrary = {}

-- Services / Modules
local RS        = game:GetService("ReplicatedStorage")
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatState         = require(RS:WaitForChild("CombatState"))
local CooldownService     = require(RS:WaitForChild("CooldownService"))
local DamageService       = require(RS:WaitForChild("DamageService"))
local GuardService        = require(RS:WaitForChild("GuardService"))
local KnockbackService    = require(RS:WaitForChild("KnockbackService"))
local ComboService        = require(RS:WaitForChild("ComboService"))
local StunService         = require(RS:WaitForChild("StunService"))
local DodgeChargeService  = require(RS:WaitForChild("DodgeChargeService"))
local AttackStateService  = require(RS:WaitForChild("AttackStateService"))
local SpeedController     = require(RS:WaitForChild("SpeedController"))
local NodeSense = require(RS:WaitForChild("NodeSense"))
local RunService = game:GetService("RunService")


local ConfirmSuccess = RS:FindFirstChild("RemoteEvents")
	and RS.RemoteEvents:FindFirstChild("ConfirmSuccess")

-- Optional (used by your Revolver and we’ll piggyback for melee if present)
local HitboxService = RS:FindFirstChild("HitboxService") and require(RS.HitboxService)

-- =============== utils =================
local function isPlayer(x)  return typeof(x) == "Instance" and x:IsA("Player") end

local function resolveCharacter(entity)
	if typeof(entity) == "Instance" then
		if entity:IsA("Player") then return entity.Character end
		if entity:IsA("Model") and entity:FindFirstChildOfClass("Humanoid") then return entity end
	elseif typeof(entity) == "table" and typeof(entity.Character) == "Instance" then
		return entity.Character
	end
	return nil
end

local function partsOf(actor)
	local char = resolveCharacter(actor)
	if not char then return nil end
	local hum  = char:FindFirstChildOfClass("Humanoid")
	local hrp  = char:FindFirstChild("HumanoidRootPart")
	return char, hum, hrp
end

local function playAndUnlock(humanoid, animId, actor)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track:Play()
	track.Stopped:Connect(function() CombatState.Unlock(actor) end)
end

-- Tiny model speed shim (players use SpeedController; models we emulate)
-- Tiny model speed shim (baseline-safe for Models; Players use SpeedController)
local _modelBaseline = setmetatable({}, {__mode="k"}) -- [Model] = base WalkSpeed
local _modelTimer    = setmetatable({}, {__mode="k"}) -- [Model] = thread

local function calcBaseline(hum)
	-- If current WS looks “bogus” (already slowed or extreme), fall back to 16
	local ws = hum.WalkSpeed
	if ws < 10 or ws > 30 then return 16 end
	return ws
end

local function baselineFor(model, hum)
	if not _modelBaseline[model] then
		_modelBaseline[model] = calcBaseline(hum)
	end
	return _modelBaseline[model]
end

local function applySpeed(actor, newSpeed, duration)
	if isPlayer(actor) then
		return SpeedController.Apply(actor, newSpeed, duration)
	end
	local char, hum = partsOf(actor)
	if not hum then return end

	-- Always restore to baseline, never to a potentially-slow snapshot
	local base = baselineFor(char, hum)

	-- cancel previous timed restore for this model
	if _modelTimer[char] then task.cancel(_modelTimer[char]) end

	hum.WalkSpeed = newSpeed
	_modelTimer[char] = task.delay(duration, function()
		if hum and hum.Parent then
			hum.WalkSpeed = base
		end
		_modelTimer[char] = nil
	end)
end


-- Faction helper: anything with IsEnemy=true is "enemy", else "player"
local function factionOf(model)
	return (model and model:GetAttribute("IsEnemy")) and "enemy" or "player"
end

-- Collect nearby valid targets (prefers HitboxService; falls back to scan), filtered by faction
local function collectTargetsAround(actor, radius)
	local char, _, root = partsOf(actor)
	if not (char and root) then return {} end

	local mine = factionOf(char)
	local raw, ok
	if HitboxService then
		if HitboxService.SphereFromPoint then
			ok, raw = pcall(HitboxService.SphereFromPoint, root.Position, radius, {humanoidsOnly = true, exclude = char})
		elseif HitboxService.Sphere then
			ok, raw = pcall(HitboxService.Sphere, root.Position, radius, {humanoidsOnly = true, exclude = char})
		elseif HitboxService.CollectHumanoids then
			ok, raw = pcall(HitboxService.CollectHumanoids, root.Position, radius, {exclude = char})
		end
	end

	local out = {}
	if ok and raw and #raw > 0 then
		for _, item in ipairs(raw) do
			local mdl = item
			if typeof(item) == "Instance" and item:IsA("Humanoid") then mdl = item.Parent end
			if typeof(mdl) == "Instance" and mdl:IsA("Model") and mdl ~= char and mdl:FindFirstChildOfClass("Humanoid") then
				if factionOf(mdl) ~= mine then
					table.insert(out, mdl)
				end
			end
		end
	else
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if inst:IsA("Model") and inst ~= char then
				local hum = inst:FindFirstChildOfClass("Humanoid")
				local hrp = inst:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and hrp and (hrp.Position - root.Position).Magnitude <= radius then
					if factionOf(inst) ~= mine then
						table.insert(out, inst)
					end
				end
			end
		end
	end
	return out
end

-- Apply a damage table to a Model/Player using DamageService; returns true if we attempted
local function dealToEntity(targetModel, dmgTbl, sourceActor)
	local asPlayer = Players:GetPlayerFromCharacter(targetModel)
	return DamageService.DealDamage(asPlayer or targetModel, dmgTbl, sourceActor)
end
-- helper (top of file is fine)
local function safeUnlock(actor, why)
	if CombatState.IsLocked(actor) then
		CombatState.Unlock(actor, why or "Node end")
	end
end


-- =============== PUNCH =================
-- ===== PUNCH (soft-stun on real hit; no guard dmg/chip; not parryable) =====
function NodeLibrary.Punch(actor)
	if CombatState.IsLocked(actor) or not CooldownService.CanUse(actor, "Punch") then return end

	CombatState.Lock(actor)
	CooldownService.Apply(actor, "Punch", 0.5)

	local char, hum = partsOf(actor)
	if not hum then safeUnlock(actor, "no humanoid"); return end

	AttackStateService.Start(actor, { duration = 0.25, nodeName = "Punch" })
	applySpeed(actor, hum.WalkSpeed * 0.5, 0.5)

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://121093639008688"
	local track = animator:LoadAnimation(anim)
	track.Stopped:Connect(function() safeUnlock(actor, "anim stopped") end)
	track:Play()

	task.delay(0.18, function()
		-- if interrupted during windup, unlock immediately
		if AttackStateService.IsInterrupted(actor) then
			safeUnlock(actor, "interrupted")
			return
		end

		local dmgTbl = {
			nodeName  = "Punch",
			type      = "Melee",
			guard     = 0,     -- per your latest tuning
			hp        = 3.3,
			chip      = 0,
			blockable = true,
			parryable = false,
		}

		local targets = collectTargetsAround(actor, 5)
		local landed = 0
		for _, mdl in ipairs(targets) do
			dealToEntity(mdl, dmgTbl, actor)
			-- soft stagger + slow (no CombatState lock)
			StunService.Apply(Players:GetPlayerFromCharacter(mdl) or mdl, 0.30, { hard = false, moveScale = 0.20 })
			landed += 1
		end

		if landed > 0 then ComboService.RegisterHit(actor) end

		-- end the attack and ensure unlock in case anim didn’t stop
		AttackStateService.Clear(actor, "done")
		safeUnlock(actor, "punch end")
	end)
end


-- =============== HEAVY =================
function NodeLibrary.Heavy(actor)
	if CombatState.IsLocked(actor) or not CooldownService.CanUse(actor, "Heavy") then return end

	CombatState.Lock(actor)
	CooldownService.Apply(actor, "Heavy", 2)

	local char, hum, root = partsOf(actor)
	if not (hum and root) then safeUnlock(actor, "no humanoid/root"); return end

	-- interruptible heavy (hyperArmor=false)
	AttackStateService.Start(actor, { duration = 0.60, nodeName = "Heavy" })

	applySpeed(actor, hum.WalkSpeed * 1.5, 0.5)
	task.delay(0.5, function() applySpeed(actor, hum.WalkSpeed * 0.25, 0.35) end)

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://90152186812447"
	local track = animator:LoadAnimation(anim)
	track.Stopped:Connect(function() safeUnlock(actor, "anim stopped") end)
	track:Play()

	task.delay(0.55, function()
		if AttackStateService.IsInterrupted(actor) then
			safeUnlock(actor, "interrupted")
			return
		end

		local dmgTbl = {
			nodeName  = "Heavy",
			type      = "MeleeHeavy",
			guard     = 30,
			hp        = 7.0,
			chip      = 2.0,
			blockable = false,
			parryable = true,
		}

		for _, mdl in ipairs(collectTargetsAround(actor, 7)) do
			dealToEntity(mdl, dmgTbl, actor)
			local theirRoot = mdl:FindFirstChild("HumanoidRootPart")
			if theirRoot then
				local dir = (theirRoot.Position - root.Position)
				KnockbackService.Apply(Players:GetPlayerFromCharacter(mdl) or mdl, dir, 90, 0.35)
			end
			-- heavy can do a short hard stun if you want; keep soft if preferred
			StunService.Apply(Players:GetPlayerFromCharacter(mdl) or mdl, 0.40, { hard = true })
		end

		if isPlayer(actor) and ConfirmSuccess then
			ConfirmSuccess:FireClient(actor, "Heavy")
		end

		AttackStateService.Clear(actor, "done")
		safeUnlock(actor, "heavy end")
	end)
end
-- Module-local state
local _isBlocking = setmetatable({}, { __mode = "k" })

local function _forceUnblock(actor, why)
	_isBlocking[actor] = nil
	pcall(function() DamageService.EndBlock(actor) end)
	pcall(function() CombatState.StopCurrentTrack(actor) end)
	pcall(function() CombatState.Unlock(actor, "ForceUnblock:" .. tostring(why or "?")) end)
	applySpeed(actor, 16, 0.05)
end

-- Only keep movement slow alive; never cancel just because GuardService says false
local function _startBlockWatch(actor)
	task.spawn(function()
		while _isBlocking[actor] do
			-- renew the slow in short pulses so it never “sticks”
			applySpeed(actor, 8, 0.30)

			local _, hum = partsOf(actor)
			if not hum or hum.Health <= 0 then
				_forceUnblock(actor, "NoHumanoid")
				break
			end

			-- Guard-break / hard stun flips PlatformStand → stop blocking immediately
			if hum.PlatformStand then
				_forceUnblock(actor, "PlatformStand")
				break
			end

			task.wait(0.12)
		end
	end)
end

-- =============== BLOCK =================
-- =============== BLOCK =================
local BLOCK_START_CD  = 0.15
local BLOCK_REARM_CD  = 0.60
local PARRY_REARM_CD  = 0.60
local lastParryAt     = setmetatable({}, {__mode="k"})

local function canBeginBlock(actor)
	return (not CombatState.IsLocked(actor))
		and CooldownService.CanUse(actor, "BlockStart")
		and CooldownService.CanUse(actor, "BlockRearm")
end

function NodeLibrary.BlockStart(actor)
	if _isBlocking[actor] then return true end
	if not canBeginBlock(actor) then return false end

	_isBlocking[actor] = true
	CombatState.Lock(actor, "Block")
	DamageService.StartBlock(actor)

	-- Parry window gate
	local ParryService = require(RS:WaitForChild("ParryService"))
	local now = os.clock()
	if (not lastParryAt[actor]) or (now - lastParryAt[actor] >= PARRY_REARM_CD) then
		ParryService.OpenWindow(actor)
		lastParryAt[actor] = now
	end

	applySpeed(actor, 8, 0.30)
	_startBlockWatch(actor)

	local _, hum = partsOf(actor)
	if not hum then
		_forceUnblock(actor, "BlockStart:NoHum")
		return false
	end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local upAnim   = Instance.new("Animation"); upAnim.AnimationId = "rbxassetid://132302528927640"
	animator:LoadAnimation(upAnim):Play()

	task.delay(0.10, function()
		if _isBlocking[actor] and CombatState.IsLocked(actor) then
			local holdAnim = Instance.new("Animation"); holdAnim.AnimationId = "rbxassetid://72122053405063"
			local holdTrack = animator:LoadAnimation(holdAnim)
			holdTrack.Looped = true
			holdTrack:Play()
			CombatState.RegisterTrack(actor, holdTrack)
		end
	end)

	if isPlayer(actor) and ConfirmSuccess then
		ConfirmSuccess:FireClient(actor, "Block")
	end
	CooldownService.Apply(actor, "BlockStart", BLOCK_START_CD)
	return true
end

function NodeLibrary.BlockEnd(actor)
	if not _isBlocking[actor] then return false end
	_forceUnblock(actor, "BlockEnd")
	CooldownService.Apply(actor, "BlockRearm", BLOCK_REARM_CD)
	return true
end


-- =============== DODGE =================
function NodeLibrary.Dodge(actor, camDir : Vector3?)
	if not DodgeChargeService.CanDodge(actor) then return end
	if CombatState.IsLocked(actor) then return end
	if not CooldownService.CanUse(actor, "Dodge") then return end
	DodgeChargeService.Consume(actor)

	CooldownService.Apply(actor, "Dodge", 1.5)
	CombatState.Lock(actor)

	local char, hum, hrp = partsOf(actor)
	if not hum or not hrp then CombatState.Unlock(actor); return end

	local anim  = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://110397380149359"
	local track = hum:LoadAnimation(anim)
	track:Play()
	track.Stopped:Connect(function() CombatState.Unlock(actor) end)

	camDir = (camDir and camDir.Magnitude > 0) and camDir.Unit or nil

	local function dash(dir, mult, dur)
		local bv = Instance.new("BodyVelocity")
		bv.Velocity = dir * 50 * mult
		bv.MaxForce = Vector3.new(1e5, 0, 1e5)
		bv.P = 1250
		bv.Parent = hrp
		task.delay(dur, function() bv:Destroy() end)
	end

	local function currentMoveDir()
		if hum.MoveDirection.Magnitude > 0 then return hum.MoveDirection.Unit end
		if camDir and camDir.Magnitude > 0 then return camDir.Unit end
		return hrp.CFrame.LookVector
	end

	dash(currentMoveDir(), 0.25, 0.2)
	task.delay(0.1, function() DamageService.GrantIFrames(actor, 1.0) end)

	task.delay(0.2, function()
		local total, step = 0, 0.05
		while total < 0.4 and hrp.Parent do
			dash(currentMoveDir(), 1.0, step)
			task.wait(step)
			total += step
		end
	end)

	task.delay(0.5, function() dash(currentMoveDir(), 1.0, 0.1) end)
	task.delay(0.6, function() dash(currentMoveDir(), 0.50, 0.4) end)
end
if RunService:IsServer() and NodeSense and NodeSense.ServerEvent then
	NodeSense.ServerEvent.Event:Connect(function(payload)
		local out = payload and payload.context and payload.context.outcome
		if out == "GuardBroken" then
			-- Payload actor is the *victim* of the guard break
			local victim = payload.actorPlayer or payload.actorModel
			if victim then
				_forceUnblock(victim, "GuardBroken")
			end
		end
	end)
end
	
return NodeLibrary
