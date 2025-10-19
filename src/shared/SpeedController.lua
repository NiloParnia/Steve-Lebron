-- ReplicatedStorage/SpeedController.lua
local SpeedController = {}

-- Key by Humanoid (works for players & NPCs). Weak refs so old humanoids GC.
local activeTimers    = setmetatable({}, { __mode = "k" })
local originalSpeeds  = setmetatable({}, { __mode = "k" })

local function resolveHumanoid(actor)
	if not actor then return nil end
	if typeof(actor) == "Instance" then
		if actor:IsA("Player") then
			local char = actor.Character
			return char and char:FindFirstChildOfClass("Humanoid")
		elseif actor:IsA("Model") then
			return actor:FindFirstChildOfClass("Humanoid")
		elseif actor:IsA("Humanoid") then
			return actor
		end
	end
	return nil
end

function SpeedController.Apply(actor, newSpeed, duration)
	local hum = resolveHumanoid(actor)
	if not hum then return end

	-- store original once per humanoid
	if originalSpeeds[hum] == nil then
		originalSpeeds[hum] = hum.WalkSpeed
	end

	-- clear previous timer for this humanoid
	if activeTimers[hum] then
		task.cancel(activeTimers[hum])
		activeTimers[hum] = nil
	end

	-- apply new speed
	hum.WalkSpeed = newSpeed

	-- optional timed reset
	local dur = tonumber(duration) or 0
	if dur > 0 then
		activeTimers[hum] = task.delay(dur, function()
			if hum.Parent then
				hum.WalkSpeed = originalSpeeds[hum] or 16
			end
			activeTimers[hum]   = nil
			originalSpeeds[hum] = nil
		end)
	end
end

function SpeedController.Reset(actor)
	local hum = resolveHumanoid(actor)
	if not hum then return end

	if originalSpeeds[hum] ~= nil then
		hum.WalkSpeed = originalSpeeds[hum]
	end
	if activeTimers[hum] then
		task.cancel(activeTimers[hum])
		activeTimers[hum] = nil
	end
	originalSpeeds[hum] = nil
end

return SpeedController
