-- StoryUnlockHandler.lua
-- Mirrors UnlockHandler, but for story unlocks (persistence only)

local RS = game:GetService("ReplicatedStorage")
local Remotes        = RS:WaitForChild("RemoteEvents")
local UnlockStory    = Remotes:WaitForChild("UnlockStory")
local ConfirmSuccess = Remotes:FindFirstChild("ConfirmSuccess")

local StoryDataService = require(script.Parent:WaitForChild("StoryDataService"))

local function notify(player, ok, message)
	if ConfirmSuccess then
		ConfirmSuccess:FireClient(player, { ok = ok, msg = message })
	end
end

local busy = setmetatable({}, { __mode = "k" }) -- weak keys

UnlockStory.OnServerEvent:Connect(function(player, storyId)
	if busy[player] then return end
	busy[player] = true
	task.delay(0.25, function() busy[player] = nil end)

	if type(storyId) ~= "string" or storyId == "" or #storyId > 60 then
		notify(player, false, "Invalid story request.")
		return
	end

	if StoryDataService.HasStory(player, storyId) then
		notify(player, true, ("Story '%s' already unlocked."):format(storyId))
		return
	end

	local added = StoryDataService.AddStory(player, storyId, true)
	if not added then
		notify(player, false, "Story unlock failed or not allowed.")
		return
	end

	notify(player, true, ("Story unlocked: %s"):format(storyId))
end)
return true
