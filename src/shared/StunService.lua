-- ReplicatedStorage/StunService
-- Hard stun = lock + physics freeze + attack interrupt.
-- Soft stun = slow only (no lock), guaranteed restore for NPC Models.
-- No use of Instance:GetAttribute; invincibility is:
--   • players: IFrameStore.IsActive(player)
--   • models:  optional BoolValue child named "Invincible" set true

local StunService = {}

------------------------------ Deps
local RS        = game:GetService("ReplicatedStorage")
local Players   = game:GetService("Players")

local CombatState        = require(RS:WaitForChild("CombatState"))
local AttackStateService = require(RS:WaitForChild("AttackStateService"))
local IFrameStore        = require(RS:WaitForChild("IFrameStore"))
local SpeedController    = require(RS:WaitForChild("SpeedController"))

-- Optional client FX
local RemoteEvents = RS:FindFirstChild("RemoteEvents")
local StunToggle   = RemoteEvents and RemoteEvents:FindFirstChild("StunToggle")

------------------------------ State
local hardEndAt       = {}   -- [entity] = os.clock() deadline
local softEndAt       = {}   -- [entity] = os.clock() deadline
local lockedByStun    = {}   -- [entity] = true if we locked
local activeTracks    = {}   -- [entity] = AnimationTrack
local savedPhys       = {}   -- [entity] = { JumpPower, AutoRotate, PlatformStand }
-- Model baselines for soft-stun restore (weak keys)
local modelBaselineWS = setmetatable({}, { __mode = "k" }) -- [Model] = base WalkSpeed


-- NPC-only slow management (players use SpeedController)
local modelOrigSpeed  = setmetatable({}, { __mode = "k" }) -- [Model] = number
local modelSlowTimer  = setmetatable({}, { __mode = "k" }) -- [Model] = thread
local slowedByStun    = setmetatable({}, { __mode = "k" }) -- [Player] = true

------------------------------ Helpers
local function isInstance(x) return typeof(x) == "Instance" end

local function asModel(ent)
	if not isInstance(ent) then return nil end
	if ent:IsA("Player") then return ent.Character end
	if ent:IsA("Model")  then return ent end
	return nil
end

local function getHumanoid(ent)
	local mdl = asModel(ent)
	return mdl and mdl:FindFirstChildOfClass("Humanoid") or nil
end

local function rootOf(ent)
	local mdl = asModel(ent)
	return mdl and mdl:FindFirstChild("HumanoidRootPart") or nil
end

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function now() return os.clock() end

local function safeEmitToggle(ent, on)
	if StunToggle and ent and ent:IsA("Player") then
		pcall(function() StunToggle:FireClient(ent, on) end)
	end
end

-- No attributes: prefer IFrameStore for players; for NPCs allow a BoolValue named "Invincible"
local function isInvincible(ent)
	if not isInstance(ent) then return false end

	if ent:IsA("Player") then
		return IFrameStore.IsActive(ent) == true
	end

	local mdl = asModel(ent)
	if not mdl then return false end
	local flag = mdl:FindFirstChild("Invincible")
	return (flag and flag:IsA("BoolValue") and flag.Value) == true
end
local function modelOf(ent)
	if ent and ent:IsA("Player") then return ent.Character end
	return ent
end

local function ensureBaselineWS(mdl, hum)
	-- If we don't have a baseline, compute a safe one.
	if not modelBaselineWS[mdl] then
		local ws = hum.WalkSpeed
		if ws < 10 or ws > 30 then ws = 16 end
		modelBaselineWS[mdl] = ws
	end
	return modelBaselineWS[mdl]
end

------------------------------ Internal clears
local function clearHard(ent)
	hardEndAt[ent] = nil

	if lockedByStun[ent] then
		CombatState.Unlock(ent, "Stun:HardClear")
		lockedByStun[ent] = nil
	end

	local hum = getHumanoid(ent)
	local s   = savedPhys[ent]
	if hum and s then
		hum.JumpPower     = s.JumpPower
		hum.AutoRotate    = s.AutoRotate
		hum.PlatformStand = s.PlatformStand
	end
	savedPhys[ent] = nil

	local track = activeTracks[ent]
	if track then pcall(function() track:Stop() end) end
	activeTracks[ent] = nil

	safeEmitToggle(ent, false)
end

local function clearSoft(ent)
	softEndAt[ent] = nil

	if ent:IsA("Player") and slowedByStun[ent] then
		-- Let SpeedController restore naturally; hard-reset only if you want:
		-- SpeedController.Reset(ent)
		slowedByStun[ent] = nil
	end

	-- Models: restore baseline WalkSpeed
local mdl = asModel(ent)
local hum = getHumanoid(ent)
if mdl and hum then
	local base = ensureBaselineWS(mdl, hum)
	hum.WalkSpeed = base
end

-- cancel any pending model timer
local mdl2 = asModel(ent)
if mdl2 and modelSlowTimer[mdl2] then
	task.cancel(modelSlowTimer[mdl2])
	modelSlowTimer[mdl2] = nil
end


	safeEmitToggle(ent, false)
end

local function scheduleHardClear(ent, untilTime)
	task.delay(math.max(0, untilTime - now()), function()
		if hardEndAt[ent] and hardEndAt[ent] <= now() then
			clearHard(ent)
		end
	end)
end

local function scheduleSoftClear(ent, untilTime)
	task.delay(math.max(0, untilTime - now()), function()
		if softEndAt[ent] and softEndAt[ent] <= now() then
			clearSoft(ent)
		end
	end)
end

------------------------------ API
-- StunService.Apply(entity, duration, opts?)
-- opts:
--   hard       = true|false (default true). false = slow only
--   moveScale  = 0..1 (soft stun speed multiplier; default 0.20)
--   animId     = stun loop AnimationId (hard only)
function StunService.Apply(entity, duration, opts)
	if not isInstance(entity) or type(duration) ~= "number" or duration <= 0 then return end

	-- invulnerability checks (no attributes)
	if isInvincible(entity) then return end

	local hard    = true
	local scale   = 0.20
	local animId  = "rbxassetid://92836816904936"

	if type(opts) == "table" then
		if opts.hard == false         then hard  = false end
		if type(opts.moveScale)=="number" then scale = clamp(opts.moveScale, 0, 1) end
		if type(opts.animId)  == "string" and #opts.animId > 0 then animId = opts.animId end
	end

	local tEnd = now() + duration

	if hard then
		-- interrupt (skips if hyper-armor)
		pcall(AttackStateService.Interrupt, entity, "Stun")

		hardEndAt[entity] = math.max(hardEndAt[entity] or 0, tEnd)

		if not lockedByStun[entity] then
			lockedByStun[entity] = true
			CombatState.Lock(entity, "Stun:Hard")
		end

		local hum = getHumanoid(entity)
		if hum then
			if not savedPhys[entity] then
				savedPhys[entity] = {
					JumpPower     = hum.JumpPower,
					AutoRotate    = hum.AutoRotate,
					PlatformStand = hum.PlatformStand,
				}
			end
			hum.JumpPower     = 0
			hum.AutoRotate    = false
			hum.PlatformStand = true

			if not activeTracks[entity] then
				local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
				local a = Instance.new("Animation")
				a.AnimationId = animId
				local track = animator:LoadAnimation(a)
				track.Looped = true
				track:Play()
				activeTracks[entity] = track
			end
		end

		safeEmitToggle(entity, true)
		scheduleHardClear(entity, hardEndAt[entity])
	else
		softEndAt[entity] = math.max(softEndAt[entity] or 0, tEnd)

		local hum = getHumanoid(entity)
		if hum then
			if entity:IsA("Player") then
				local base   = hum.WalkSpeed
				local target = math.max(1, base * scale)
				slowedByStun[entity] = true
				SpeedController.Apply(entity, target, duration)
			else
				-- Models: baseline-safe slow so we never get “perma-slow”
				local mdl = asModel(entity)
				if mdl then
					if modelSlowTimer[mdl] then task.cancel(modelSlowTimer[mdl]) end

					local hum = getHumanoid(entity)
					if hum then
						local base = ensureBaselineWS(mdl, hum)
						hum.WalkSpeed = math.max(1, base * scale)

						modelSlowTimer[mdl] = task.delay(duration, function()
							-- if someone extended, honor it (existing logic)
							if softEndAt[entity] and softEndAt[entity] > now() then
								scheduleSoftClear(entity, softEndAt[entity])
							else
								-- restore to BASELINE (not to whatever was current)
								if hum and hum.Parent then
									hum.WalkSpeed = base
								end
								modelSlowTimer[mdl] = nil
								-- we keep the baseline for future uses; do not nil it
								softEndAt[entity] = nil
							end
						end)
					end
				end

			end
		end

		safeEmitToggle(entity, true)
		scheduleSoftClear(entity, softEndAt[entity])
	end
end

function StunService.Clear(entity)
	if not isInstance(entity) then return end
	if hardEndAt[entity] then clearHard(entity) end
	if softEndAt[entity] then clearSoft(entity) end
end

function StunService.IsStunned(entity)
	local t = hardEndAt[entity]
	return t ~= nil and t > now()
end

------------------------------ Cleanup
Players.PlayerRemoving:Connect(function(plr)
	StunService.Clear(plr)
end)

return StunService
