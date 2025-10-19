-- PlayerDataService.lua (ServerScriptService)
-- Single source of truth for player data (ProfileService-backed)
-- Public API: GetProfile, GetData, WaitForProfile, HasUnlock, AddUnlock, RemoveUnlock, Save

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local ProfileService      = require(ServerScriptService:WaitForChild("ProfileService"))

-- Bump only if you intentionally migrate to a new store
local PROFILE_STORE = "PlayerData_v1"

-- ---------- DEFAULTS (IMMUTABLE) ----------	
local DEFAULTS = {
	SchemaVersion = 1,
	Unlocks = { "Punch", "Heavy", "Dodge", "BlockStart", "BlockEnd" },
	-- Future fields: Cash = 0, etc.
}
table.freeze(DEFAULTS)

-- ---------- ALLOWLIST (cached from RS/Unlockables + defaults) ----------
local ALLOWED -- lazy-populated set
local function refreshAllowed()
	local t = {}
	local folder = ReplicatedStorage:FindFirstChild("Unlockables")
	if folder then
		for _, sv in ipairs(folder:GetChildren()) do
			if sv:IsA("StringValue") and type(sv.Value) == "string" and sv.Value ~= "" then
				t[sv.Value] = true
			end
		end
	end
	for _, def in ipairs(DEFAULTS.Unlocks) do t[def] = true end
	ALLOWED = t
end
local function getAllowed()
	if not ALLOWED then refreshAllowed() end
	return ALLOWED
end
-- live refresh if the folder changes at runtime
local unlockFolder = ReplicatedStorage:FindFirstChild("Unlockables")
if unlockFolder then
	unlockFolder.ChildAdded:Connect(refreshAllowed)
	unlockFolder.ChildRemoved:Connect(refreshAllowed)
end

-- ---------- INTERNALS ----------
local store    = ProfileService.GetProfileStore(PROFILE_STORE, DEFAULTS)
local Profiles = {} -- [player] = live profile object

local function cloneArray(a)
	local out = {}
	for i, v in ipairs(a) do out[i] = v end
	return out
end

local function sanitizeUnlocks(profile)
	local data = profile.Data
	data.Unlocks = data.Unlocks or {}
	local allowed = getAllowed()
	local cleaned, seen, changed = {}, {}, false
	for _, name in ipairs(data.Unlocks) do
		if allowed[name] and not seen[name] then
			seen[name] = true
			table.insert(cleaned, name)
		else
			changed = true -- drop junk/dupe/disallowed
		end
	end
	-- Ensure not empty (prevent soft-lock)
	if #cleaned == 0 then
		cleaned = cloneArray(DEFAULTS.Unlocks)
		changed = true
	end
	if changed then
		data.Unlocks = cleaned
		pcall(function() profile:Save() end)
	end
end

local function onRelease(player)
	Profiles[player] = nil
	if player and player.Parent then
		player:Kick("Your data session was released elsewhere. Please rejoin.")
	end
end

-- ---------- PUBLIC API ----------
local PlayerDataService = {}

function PlayerDataService.GetProfile(player)
	return Profiles[player]
end

function PlayerDataService.GetData(player)
	local p = Profiles[player]
	if not p then return nil end
	-- Return a shallow clone so callers can't mutate the live table
	return table.clone(p.Data)
end

function PlayerDataService.WaitForProfile(player, timeout)
	local t0, to = os.clock(), (timeout or 10)
	while os.clock() - t0 < to do
		local p = Profiles[player]
		if p then return p end
		task.wait()
	end
	return nil
end

function PlayerDataService.HasUnlock(player, nodeName)
	local p = Profiles[player]
	if not p or type(nodeName) ~= "string" or nodeName == "" then return false end
	for _, n in ipairs(p.Data.Unlocks or {}) do
		if n == nodeName then return true end
	end
	return false
end

-- basic per-player write lock (avoids interleaving unlock/remove bursts)
local Busy = setmetatable({}, { __mode = "k" })
local function withLock(player, fn)
	while Busy[player] do task.wait() end
	Busy[player] = true
	local ok, r = pcall(fn)
	Busy[player] = nil
	if not ok then warn("[PlayerDataService] Error:", r) end
	return ok and r or false
end

function PlayerDataService.AddUnlock(player, nodeName, saveNow)
	if type(nodeName) ~= "string" or nodeName == "" then return false end
	local profile = Profiles[player]; if not profile then return false end
	local allowed = getAllowed()
	if not allowed[nodeName] then
		warn("[PlayerDataService] AddUnlock rejected (not allowed):", nodeName)
		return false
	end
	return withLock(player, function()
		local list = profile.Data.Unlocks or {}
		for _, n in ipairs(list) do if n == nodeName then return false end end
		table.insert(list, nodeName)
		profile.Data.Unlocks = list
		if saveNow and profile.Save then pcall(function() profile:Save() end) end
		return true
	end)
end

function PlayerDataService.RemoveUnlock(player, nodeName, saveNow)
	if type(nodeName) ~= "string" or nodeName == "" then return false end
	local profile = Profiles[player]; if not profile then return false end
	return withLock(player, function()
		local list = profile.Data.Unlocks or {}
		local out, changed = {}, false
		for _, n in ipairs(list) do
			if n ~= nodeName then table.insert(out, n) else changed = true end
		end
		if not changed then return false end
		profile.Data.Unlocks = out
		if saveNow and profile.Save then pcall(function() profile:Save() end) end
		return true
	end)
end

function PlayerDataService.Save(player)
	local profile = Profiles[player]
	if profile and profile.Save then
		local ok, err = pcall(function() profile:Save() end)
		if not ok then warn("[PlayerDataService] Save error:", err) end
		return ok
	end
	return false
end

-- ---------- LIFECYCLE (load/release) ----------
Players.PlayerAdded:Connect(function(player)
	local key = ("Player_%d"):format(player.UserId)
	local profile = store:LoadProfileAsync(key, "ForceLoad")
	if not profile then
		player:Kick("Data failed to load. Please rejoin.")
		return
	end
	-- Player may have left while datastore was busy
	if not player.Parent then
		profile:Release()
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile() -- adds new keys from DEFAULTS; doesn't overwrite arrays
	sanitizeUnlocks(profile)
	profile:ListenToRelease(function()
		onRelease(player)
	end)
	Profiles[player] = profile
end)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile then
		profile:Release()
		Profiles[player] = nil
	end
end)

game:BindToClose(function()
	local snapshot = {}
	for plr, prof in pairs(Profiles) do snapshot[plr] = prof end
	for _, prof in pairs(snapshot) do prof:Release() end
end)

return PlayerDataService