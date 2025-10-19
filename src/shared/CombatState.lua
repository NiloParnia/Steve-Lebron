-- CombatState (ref-counted, key-normalized)
-- Drop-in replacement to prevent permanent locks from mixed Player/Model usage.

local CombatState = {}

local Players = game:GetService("Players")

-- ========== internal state ==========
local lockCount     = setmetatable({}, { __mode = "k" }) -- [key] = int
local activeTracks  = setmetatable({}, { __mode = "k" }) -- [key] = AnimationTrack
local unlockBuffer  = setmetatable({}, { __mode = "k" }) -- [key] = tick()
local lastEvent     = setmetatable({}, { __mode = "k" }) -- [key] = { kind, reason, when, caller }

-- ---------- key normalization ----------
local function asModel(ent)
	if typeof(ent) ~= "Instance" then return nil end
	if ent:IsA("Player") then return ent.Character end
	if ent:IsA("Model") then return ent end
	return ent:FindFirstAncestorOfClass("Model")
end

local function normKey(entity)
	if typeof(entity) ~= "Instance" then return entity end
	if entity:IsA("Player") then return entity end
	if entity:IsA("Model") then
		return Players:GetPlayerFromCharacter(entity) or entity
	end
	local mdl = asModel(entity)
	return (mdl and (Players:GetPlayerFromCharacter(mdl) or mdl)) or entity
end

local function mark(key, kind, reason)
	lastEvent[key] = {
		kind   = kind,                            -- "lock" | "unlock" | "unlock(force)"
		reason = reason or "unspecified",
		when   = os.clock(),
		caller = debug.info(3, "s") or "unknown",
		count  = lockCount[key] or 0,
	}
end

-- ========== public API ==========

function CombatState.Lock(entity, reason)
	local key = normKey(entity); if not key then return end
	lockCount[key] = (lockCount[key] or 0) + 1
	mark(key, "lock", reason)
end

function CombatState.Unlock(entity, reason)
	local key = normKey(entity); if not key then return end
	local n = (lockCount[key] or 0) - 1
	if n <= 0 then
		lockCount[key] = nil
	else
		lockCount[key] = n
	end
	mark(key, "unlock", reason)
end

function CombatState.ForceUnlock(entity, reason)
	local key = normKey(entity); if not key then return end
	lockCount[key] = nil
	mark(key, "unlock(force)", reason or "manual")
end

function CombatState.IsLocked(entity)
	local key = normKey(entity); if not key then return false end
	return (lockCount[key] or 0) > 0
end

-- Optional: short grace period after unlock (unchanged semantics)
function CombatState.SetUnlockBuffer(entity, duration)
	local key = normKey(entity); if not key then return end
	unlockBuffer[key] = tick() + (duration or 0)
end

function CombatState.RecentlyUnlocked(entity)
	local key = normKey(entity); if not key then return false end
	return (unlockBuffer[key] or 0) > tick()
end

-- Animation helpers (key-normalized)
function CombatState.RegisterTrack(entity, track)
	local key = normKey(entity); if not key then return end
	if activeTracks[key] then
		pcall(function() activeTracks[key]:Stop() end)
	end
	activeTracks[key] = track
end

function CombatState.StopCurrentTrack(entity)
	local key = normKey(entity); if not key then return end
	if activeTracks[key] then
		pcall(function() activeTracks[key]:Stop() end)
		activeTracks[key] = nil
	end
end

-- Cleanup for a given entity/key
function CombatState.Cleanup(entity)
	local key = normKey(entity); if not key then return end
	lockCount[key]    = nil
	activeTracks[key] = nil
	unlockBuffer[key] = nil
	lastEvent[key]    = nil
end

-- Debug helpers
function CombatState.GetLockInfo(entity)
	local key = normKey(entity); if not key then return nil end
	return {
		count  = lockCount[key] or 0,
		last   = lastEvent[key],
		hasTrack = activeTracks[key] ~= nil,
	}
end

function CombatState.DebugPrint(entity, label)
	local info = CombatState.GetLockInfo(entity)
	print(("[CombatState] %s  count=%s  hasTrack=%s  last=%s/%s @%.2f from %s")
		:format(
			label or tostring(entity),
			info and info.count or 0,
			info and tostring(info.hasTrack) or "false",
			info and info.last and info.last.kind or "nil",
			info and info.last and tostring(info.last.reason) or "nil",
			info and info.last and info.last.when or 0,
			info and info.last and tostring(info.last.caller) or "?"
		)
	)
end

return CombatState
