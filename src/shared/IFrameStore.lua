---------------------------------------------------------------------
-- IFrameStore • authoritative registry for active i-frames
-- Emits NodeSense outcomes:
--   DodgeStart   (when i-frames begin)
--   DodgeRefresh (when an active window is extended/refreshed)
--   DodgeEnd     (when i-frames end naturally or via Clear)
---------------------------------------------------------------------
local IFrameStore = {}

local RS        = game:GetService("ReplicatedStorage")
local NodeSense = require(RS:WaitForChild("NodeSense"))

-- [player] = expiry tick()
local registry = {}

-- Optional: last start tick, helps with debugging/telemetry
local lastStart = {}  -- [player] = tick()

-- Internal: emit helper
local function emit(player, outcome, ctx)
	-- Player = actor; nodeName = "Dodge"
	-- NodeSense dedup protects against bursty repeats
	pcall(function()
		NodeSense.EmitOutcome(player, "Dodge", outcome, ctx or {})
	end)
end

-- Give player i-frames for `duration` seconds
-- If already active, this refreshes/extends the window and emits DodgeRefresh
function IFrameStore.Grant(player, duration, reason)
	if not player or type(duration) ~= "number" or duration <= 0 then return end

	local now      = tick()
	local prevExp  = registry[player] or 0
	local wasActive= prevExp > now

	local newExp   = now + duration
	registry[player] = newExp
	if not wasActive then
		lastStart[player] = now
		emit(player, "DodgeStart", { duration = duration, expiresAt = newExp, reason = reason or "Dodge" })
	else
		-- Active window extended/refreshed
		emit(player, "DodgeRefresh", {
			added     = duration,
			expiresAt = newExp,
			remaining = newExp - now,
			reason    = reason or "Dodge"
		})
	end

	-- Only the latest grant should end the window
	local thisExp = newExp
	task.delay(duration, function()
		-- If no newer grant occurred and time has passed, end it
		if registry[player] == thisExp and thisExp <= tick() then
			registry[player] = nil
			lastStart[player] = nil
			emit(player, "DodgeEnd", { reason = reason or "Dodge" })
		end
	end)
end

-- Query: is the player currently invulnerable?
function IFrameStore.IsActive(player)
	return (registry[player] or 0) > tick()
end

-- Optional: remaining seconds (0 if none)
function IFrameStore.GetRemaining(player)
	local rem = (registry[player] or 0) - tick()
	return rem > 0 and rem or 0
end

-- Optional: force-clear i-frames early (emits DodgeEnd once)
function IFrameStore.Clear(player, reason)
	local wasActive = IFrameStore.IsActive(player)
	registry[player] = nil
	lastStart[player] = nil
	if wasActive then
		emit(player, "DodgeEnd", { reason = reason or "Clear" })
		return true
	end
	return false
end

return IFrameStore
