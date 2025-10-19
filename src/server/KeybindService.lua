-- KeybindService.lua
-- Persists per-player keybinds (max 5). Keys: 1-0, Z-M.
-- Enforces that only *unlockable* nodes (mirrored in RS/Unlockables) can be bound.

local RS = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local ALLOWED_KEYS = {
	One=true, Two=true, Three=true, Four=true, Five=true,
	Six=true, Seven=true, Eight=true, Nine=true, Zero=true,
	Z=true, X=true, C=true, V=true, B=true, N=true, M=true,
}

-- Live cache of unlockable node names (from RS/Unlockables)
local UNLOCKABLES_SET -- [name]=true

local function refreshUnlockables()
	local set = {}
	local folder = RS:FindFirstChild("Unlockables")
	if folder then
		for _, sv in ipairs(folder:GetChildren()) do
			if sv:IsA("StringValue") and sv.Value ~= "" then
				set[sv.Value] = true
			end
		end
	end
	UNLOCKABLES_SET = set
end
refreshUnlockables()
local uFolder = RS:FindFirstChild("Unlockables")
if uFolder then
	uFolder.ChildAdded:Connect(refreshUnlockables)
	uFolder.ChildRemoved:Connect(refreshUnlockables)
end
local function isUnlockable(name) return UNLOCKABLES_SET and UNLOCKABLES_SET[name] or false end

local Busy = setmetatable({}, { __mode = "k" })

local KeybindService = {}

local function ensure(profile)
	local d = profile.Data
	d.Keybinds = d.Keybinds or {} -- map: keyName -> nodeName
end

local function countBinds(map)
	local n = 0
	for _k, v in pairs(map) do if v and v ~= "" then n += 1 end end
	return n
end

function KeybindService.GetAll(player)
	local p = PlayerDataService.GetProfile(player)
	if not p then return {} end
	ensure(p)
	local out = {}
	for k, v in pairs(p.Data.Keybinds) do out[k] = v end
	return out
end

-- set or clear (nodeName == nil/"" to clear)
function KeybindService.Set(player, keyName, nodeName)
	if type(keyName) ~= "string" or keyName == "" or not ALLOWED_KEYS[keyName] then
		return false, "Key not allowed."
	end
	local prof = PlayerDataService.GetProfile(player)
	if not prof then return false, "Profile not ready." end
	ensure(prof)

	-- Clear always allowed
	if not nodeName or nodeName == "" then
		prof.Data.Keybinds[keyName] = nil
		if prof.Save then pcall(function() prof:Save() end) end
		return true, "Unbound."
	end

	-- Only unlockables may be bound (e.g., Revolver), AND you must own it
	if not isUnlockable(nodeName) then
		return false, "Only unlockable moves can be bound."
	end
	if not PlayerDataService.HasUnlock(player, nodeName) then
		return false, "You don't have that unlock yet."
	end

	if Busy[player] then return false, "Busy." end
	Busy[player] = true

	local ok, msg = pcall(function()
		local binds = prof.Data.Keybinds
		local hadBefore = binds[keyName] ~= nil and binds[keyName] ~= ""
		if not hadBefore and countBinds(binds) >= 5 then
			error("You can only have 5 active keybinds.")
		end
		binds[keyName] = nodeName
		if prof.Save then pcall(function() prof:Save() end) end
	end)

	Busy[player] = nil
	if not ok then return false, msg end
	return true, "Saved."
end

return KeybindService
