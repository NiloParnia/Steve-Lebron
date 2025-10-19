local CooldownService = {}

local cooldowns = {}

-- Checks if the player can use a specific action
function CooldownService.CanUse(player, action)
	if not player then return false end
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then return true end

	local timestamp = playerCooldowns[action]
	return not timestamp or tick() >= timestamp
end

-- Sets a cooldown for a specific action
function CooldownService.Apply(player, action, duration)
	if not player then return end
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][action] = tick() + duration
end

-- Optionally reset cooldowns for a player (e.g., on death or reset)
function CooldownService.Clear(player)
	cooldowns[player] = nil
end

-- Optional debug readout
function CooldownService.GetRemaining(player, action)
	local ts = cooldowns[player] and cooldowns[player][action]
	if ts then
		return math.max(0, ts - tick())
	end
	return 0
end

return CooldownService
