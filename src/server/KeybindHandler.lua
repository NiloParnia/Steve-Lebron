-- src/server/KeybindHandler.lua
-- Wires RemoteFunctions for keybinds and discoverable unlocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sss               = script.Parent

local PlayerDataService = require(sss:WaitForChild("PlayerDataService"))

local Remotes           = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetKeybindsRF     = Remotes:WaitForChild("GetKeybinds")
local SetKeybindRF      = Remotes:WaitForChild("SetKeybind")
local GetUnlockedNodesRF= Remotes:WaitForChild("GetUnlockedNodes")

-- ---------------------------------------------------------------------------
-- Build allow-set of unlockable node names (tolerant to different sources)
local UNLOCKABLES_SET = {}

local function addToSet(name)
	if type(name) == "string" and #name > 0 then
		UNLOCKABLES_SET[name] = true
	end
end

-- Preferred: module returns list or map
do
	local ok, allow = pcall(function()
		return require(sss:WaitForChild("StoryUnlockables"))
	end)
	if ok and allow then
		if typeof(allow) == "table" then
			for k, v in pairs(allow) do
				if typeof(k) == "string" and (v == true or typeof(v) == "table") then
					addToSet(k)
				elseif typeof(v) == "string" then
					addToSet(v)
				end
			end
		end
	end
end

-- Fallback: scan folders by child names
local function harvestFolder(folderName)
	local f = ReplicatedStorage:FindFirstChild(folderName)
	if f then
		for _, child in ipairs(f:GetChildren()) do
			addToSet(child.Name)
		end
	end
end

if next(UNLOCKABLES_SET) == nil then
	harvestFolder("StoryUnlockables")
	harvestFolder("Unlockables")
end

-- ---------------------------------------------------------------------------
-- Helpers
local function getData(player)
	return PlayerDataService.GetData(player) or {}
end

local function getBinds(player)
	local data = getData(player)
	data.Keybinds = data.Keybinds or {}
	return data.Keybinds, data
end

-- ---------------------------------------------------------------------------
-- GetKeybinds: returns player's keybind mapping (no defaults forced)
GetKeybindsRF.OnServerInvoke = function(player)
	local binds = getBinds(player)
	-- Return a shallow copy to avoid accidental mutation on client
	local copy = {}
	for k, v in pairs(binds) do copy[k] = v end
	return copy
end

-- SetKeybind: action -> key (e.g., "Block" -> "F")
SetKeybindRF.OnServerInvoke = function(player, action, key)
	if typeof(action) ~= "string" or action == "" then
		return false, "Invalid action"
	end
	if typeof(key) ~= "string" or key == "" then
		return false, "Invalid key"
	end

	local binds, data = getBinds(player)
	binds[action] = key
	-- If your PlayerDataService has an explicit save, call it here (safe pcall):
	if PlayerDataService.Save then
		pcall(PlayerDataService.Save, player, data)
	end

	local copy = {}
	for k, v in pairs(binds) do copy[k] = v end
	return true, copy
end

-- GetUnlockedNodes: intersection of player's Unlocks with allow-set
GetUnlockedNodesRF.OnServerInvoke = function(player)
	local data = getData(player)
	local out = {}
	for _, n in ipairs((data and data.Unlocks) or {}) do
		if UNLOCKABLES_SET[n] then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

return true
