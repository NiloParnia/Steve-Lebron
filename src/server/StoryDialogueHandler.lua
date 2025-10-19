-- StoryDataService.lua
-- Wrapper over PlayerDataService for StoryUnlocks + lightweight flags

local RS = game:GetService("ReplicatedStorage")
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

-- -------- Allow-list (RS/StoryUnlockables) --------
local ALLOWED
local function refreshAllowed()
	ALLOWED = {}
	local folder = RS:FindFirstChild("StoryUnlockables")
	if folder then
		for _, sv in ipairs(folder:GetChildren()) do
			if sv:IsA("StringValue") and type(sv.Value) == "string" and sv.Value ~= "" then
				ALLOWED[sv.Value] = true
			end
		end
	end
end
local function getAllowed()
	if not ALLOWED then refreshAllowed() end
	return ALLOWED
end
local storyFolder = RS:FindFirstChild("StoryUnlockables")
if storyFolder then
	storyFolder.ChildAdded:Connect(refreshAllowed)
	storyFolder.ChildRemoved:Connect(refreshAllowed)
end

-- -------- Internals --------
local Busy = setmetatable({}, { __mode = "k" })

local StoryDataService = {}

local function ensureFields(profile)
	local data = profile.Data
	data.StoryUnlocks = data.StoryUnlocks or {}   -- map: [id]=true
	data.StoryFlags   = data.StoryFlags   or {}   -- map: [key]=primitive
end

function StoryDataService.HasStory(player, storyId)
	local profile = PlayerDataService.GetProfile(player)
	if not profile or type(storyId) ~= "string" or storyId == "" then return false end
	ensureFields(profile)
	return profile.Data.StoryUnlocks[storyId] == true
end

function StoryDataService.AddStory(player, storyId, saveNow)
	if type(storyId) ~= "string" or storyId == "" then return false end
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return false end
	ensureFields(profile)
	local allowed = getAllowed()
	if not allowed[storyId] then
		warn("[StoryDataService] AddStory rejected (not allowed):", storyId)
		return false
	end
	if Busy[player] then return false end
	Busy[player] = true
	local ok, res = pcall(function()
		if profile.Data.StoryUnlocks[storyId] then return false end
		profile.Data.StoryUnlocks[storyId] = true
		if saveNow and profile.Save then pcall(function() profile:Save() end) end
		return true
	end)
	Busy[player] = nil
	if not ok then warn("[StoryDataService] Error:", res) return false end
	return res
end

function StoryDataService.GetFlags(player)
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return nil end
	ensureFields(profile)
	return table.clone(profile.Data.StoryFlags)
end

function StoryDataService.GetFlag(player, key)
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return nil end
	ensureFields(profile)
	return profile.Data.StoryFlags[key]
end

function StoryDataService.SetFlag(player, key, value, saveNow)
	if type(key) ~= "string" or key == "" then return false end
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return false end
	ensureFields(profile)
	profile.Data.StoryFlags[key] = value
	if saveNow and profile.Save then pcall(function() profile:Save() end) end
	return true
end

return StoryDataService
