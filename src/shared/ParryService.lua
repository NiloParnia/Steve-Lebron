---------------------------------------------------------------------
-- ParryService  (ReplicatedStorage)
-- • Block input calls OpenWindow(player[, duration]) → opens a parry window.
-- • If the defender is struck during the window, Try(attacker, defender)
--   returns true, stuns attacker, ends defender’s block, and grants brief
--   invulnerability via IFrameStore.
--
-- NodeSense emits (telemetry only; no "Parried" here):
--   ParryWindowStart   { duration }
--   ParryWindowRefresh { added, remaining }
--   ParryWindowEnd     { reason = "Consumed" | "Timeout" | "Clear" }
---------------------------------------------------------------------
local ParryService = {}

------------------------------ SERVICES
local RS               = game:GetService("ReplicatedStorage")
local Players          = game:GetService("Players")

local StunService      = require(RS:WaitForChild("StunService"))
local GuardService     = require(RS:WaitForChild("GuardService"))
local IFrameStore      = require(RS:WaitForChild("IFrameStore"))
local NodeSense        = require(RS:WaitForChild("NodeSense"))

------------------------------ CONFIG
local DEFAULT_WINDOW = 0.3   -- parry timing window (sec)
local PARRY_STUN     = 2.5   -- stun applied to attacker (sec)
local IMMUNITY_TIME  = 1.0   -- defender i-frames after parry (sec)

------------------------------ STATE
-- [defender] = expiry tick()
local windowExpires = {}
-- [defender] = expiry tick()
local immunity      = {}

------------------------------ HELPERS
local function asInstance(ent)
	if typeof(ent) == "Instance" then
		return ent
	elseif typeof(ent) == "table" and typeof(ent.Character) == "Instance" then
		return ent.Character
	end
	return nil
end

local function emit(actor, outcome, ctx)
	pcall(function()
		NodeSense.EmitOutcome(actor, "Parry", outcome, ctx or {})
	end)
end

------------------------------ API
function ParryService.OpenWindow(defender, duration)
	if not defender then return end
	local now = tick()
	local dur = tonumber(duration) or DEFAULT_WINDOW
	local prev = windowExpires[defender] or 0
	local wasActive = prev > now

	local newExp = now + dur
	windowExpires[defender] = newExp

	if wasActive then
		emit(defender, "ParryWindowRefresh", {
			added     = dur,
			remaining = newExp - now,
		})
	else
		emit(defender, "ParryWindowStart", { duration = dur })
	end

	-- schedule end (only ends if expiry wasn't extended)
	local thisExp = newExp
	task.delay(dur, function()
		if windowExpires[defender] == thisExp and thisExp <= tick() then
			windowExpires[defender] = nil
			emit(defender, "ParryWindowEnd", { reason = "Timeout" })
		end
	end)
end

function ParryService.IsActive(defender)
	return (windowExpires[defender] or 0) > tick()
end

function ParryService.HasImmunity(ent)
	return (immunity[ent] or 0) > tick()
end

-- Optional manual clear (e.g., player released block early)
function ParryService.ClearWindow(defender)
	if not defender then return false end
	if not ParryService.IsActive(defender) then return false end
	windowExpires[defender] = nil
	emit(defender, "ParryWindowEnd", { reason = "Clear" })
	return true
end

-- Returns true on successful parry; false otherwise.
function ParryService.Try(attacker, defender)
	if not ParryService.IsActive(defender) then return false end

	-- consume window
	windowExpires[defender] = nil
	emit(defender, "ParryWindowEnd", { reason = "Consumed" })

	-----------------------------------------------------------------
	-- punish attacker
	-----------------------------------------------------------------
	local inst = asInstance(attacker)
	if inst then
		StunService.Apply(inst, PARRY_STUN)
	end

	-----------------------------------------------------------------
	-- defender: end block + grant brief i-frames (invulnerability)
	-----------------------------------------------------------------
	GuardService.EndBlock(defender)
	IFrameStore.Grant(defender, IMMUNITY_TIME, "Parry")
	immunity[defender] = tick() + IMMUNITY_TIME

	return true
end

------------------------------ CLEANUP
Players.PlayerRemoving:Connect(function(plr)
	windowExpires[plr] = nil
	immunity[plr]      = nil
end)

---------------------------------------------------------------------
return ParryService
