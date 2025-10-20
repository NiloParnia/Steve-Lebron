-- src/server/GameInit.server.lua
-- Boot order: (1) create remotes, (2) create scaffolding folders, (3) non-blocking requires, (4) player lifecycle, (5) story/keybind systems.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local function logWarn(...)
	warn("[GameInit]", ...)
end

-- 1) REMOTES FIRST -----------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "RemoteEvents"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local ev = remotes:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotes
	end
	return ev
end

local function ensureRemoteFunction(name)
	local rf = remotes:FindFirstChild(name)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = remotes
	end
	return rf
end

-- Events used elsewhere (NPCs/UI expect these early)
ensureRemote("ActivateNode")
ensureRemote("UnlockNode")
ensureRemote("NodeActions")
ensureRemote("ConfirmSuccess")
ensureRemote("CooldownNotice")
ensureRemote("DodgeCharges")
ensureRemote("UnlockStory")
ensureRemote("BeginDialogue")
ensureRemote("ChooseOption")
ensureRemote("DialogueUpdate")

-- RFs for keybinds
ensureRemoteFunction("GetKeybinds")
ensureRemoteFunction("SetKeybind")
ensureRemoteFunction("GetUnlockedNodes")

-- 2) SCAFFOLD FOLDERS --------------------------------------------------------
local storyAllow = ReplicatedStorage:FindFirstChild("StoryUnlockables")
if not storyAllow then
	storyAllow = Instance.new("Folder")
	storyAllow.Name = "StoryUnlockables"
	storyAllow.Parent = ReplicatedStorage
end

local stories = ReplicatedStorage:FindFirstChild("Stories")
if not stories then
	stories = Instance.new("Folder")
	stories.Name = "Stories"
	stories.Parent = ReplicatedStorage
end

-- 3) NON-BLOCKING REQUIRES ---------------------------------------------------
local PlayerDataService
do
	local mod = SSS:FindFirstChild("PlayerDataService")
	if not mod then
		logWarn("Missing ServerScriptService.PlayerDataService (will degrade gracefully)")
	else
		local ok, res = pcall(function() return require(mod) end)
		if not ok then
			logWarn("PlayerDataService require failed:", res)
		else
			PlayerDataService = res
		end
	end
end

local NodeManager
do
	local mod = ReplicatedStorage:FindFirstChild("NodeManager")
	if not mod then
		logWarn("Missing ReplicatedStorage.NodeManager (unlocks may not load)")
	else
		local ok, res = pcall(function() return require(mod) end)
		if not ok then
			logWarn("NodeManager require failed:", res)
		else
			NodeManager = res
		end
	end
end

-- 4) PLAYER LIFECYCLE --------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	if PlayerDataService and PlayerDataService.WaitForProfile then
		local profile = PlayerDataService.WaitForProfile(player, 10)
		if not profile then
			logWarn("Profile failed to load for", player.Name)
			return
		end
		if NodeManager and NodeManager.LoadUnlocked then
			NodeManager.LoadUnlocked(player, profile)
		end
	else
		logWarn("PlayerDataService/NodeManager not ready; skipping unlock load for", player.Name)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if NodeManager and NodeManager.Unload then
		NodeManager.Unload(player)
	end
end)

-- 5) STORY/KEYBIND SYSTEMS ---------------------------------------------------
local function saferequire(where, name)
	local inst = where:FindFirstChild(name)
	if not inst then logWarn("Missing", where.Name .. "." .. name); return end
	local ok, err = pcall(require, inst)
	if not ok then logWarn("Require failed for", name, ":", err) end
end

saferequire(SSS, "StoryDataService")
saferequire(SSS, "StoryUnlockHandler")
saferequire(SSS, "StoryDialogueHandler")
saferequire(SSS, "StoryUnlockables") -- module listing unlock rules; not the RS folder
saferequire(SSS, "KeybindHandler")

print("[GameInit] Boot complete.")
return true
