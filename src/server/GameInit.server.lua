-- GameInit.lua (ServerScriptService)
-- Creates remotes and wires load/unload hooks

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local NodeManager       = require(game:GetService("ReplicatedStorage"):WaitForChild("NodeManager"))

-- Remote bootstrap -----------------------------------------------------------
local function ensureRemote(folder, name)
	local ev = folder:FindFirstChild(name)
	if not ev then ev = Instance.new("RemoteEvent"); ev.Name = name; ev.Parent = folder end
	return ev
end

local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
remotes.Name = "RemoteEvents"
remotes.Parent = ReplicatedStorage

ensureRemote(remotes, "ActivateNode")   -- client -> server (fire a node)
ensureRemote(remotes, "UnlockNode")     -- client -> server (unlock a node)
ensureRemote(remotes, "NodeActions")    -- client -> server (menus, etc.)
ensureRemote(remotes, "ConfirmSuccess") -- server -> client (toast)
ensureRemote(remotes, "CooldownNotice") -- server -> client (cooldown UI)
ensureRemote(remotes, "DodgeCharges")   -- server -> client (dodge UI)
-- Dialogue/Story remotes
ensureRemote(remotes, "UnlockStory")
ensureRemote(remotes, "BeginDialogue")
ensureRemote(remotes, "ChooseOption")
ensureRemote(remotes, "DialogueUpdate")

-- RemoteFunction helper
local function ensureRemoteFunction(folder, name)
	local rf = folder:FindFirstChild(name)
	if not rf then rf = Instance.new("RemoteFunction"); rf.Name = name; rf.Parent = folder end
	return rf
end
ensureRemoteFunction(remotes, "GetStoryUnlocks")

-- Ensure folders exist
local storyAllow = ReplicatedStorage:FindFirstChild("StoryUnlockables") or Instance.new("Folder")
storyAllow.Name = "StoryUnlockables"; storyAllow.Parent = ReplicatedStorage
local stories = ReplicatedStorage:FindFirstChild("Stories") or Instance.new("Folder")
stories.Name = "Stories"; stories.Parent = ReplicatedStorage


-- Player lifecycle -----------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	local profile = PlayerDataService.WaitForProfile(player, 10)
	if not profile then
		warn("[GameInit] Profile failed to load for", player.Name)
		return
	end
	NodeManager.LoadUnlocked(player, profile)
end)

Players.PlayerRemoving:Connect(function(player)
	NodeManager.Unload(player)
end)

-- Boot story systems
require(script.Parent:WaitForChild("StoryDataService"))
require(script.Parent:WaitForChild("StoryUnlockHandler"))
require(script.Parent:WaitForChild("StoryDialogueHandler"))
require(script.Parent:WaitForChild("StoryUnlockables")) -- or StoryList if you switch to auto-discovery


-- ServerScriptService/DiagProbe.server.lua  (TEMP)
local RS = game:GetService("ReplicatedStorage")
local RE = RS:WaitForChild("RemoteEvents")
local Begin = RE:WaitForChild("BeginDialogue")
local Update = RE:WaitForChild("DialogueUpdate")


-- after ensureRemote(...) lines
local s = script.Parent
require(s:WaitForChild("StoryDataService"))
require(s:WaitForChild("StoryUnlockHandler"))
require(s:WaitForChild("StoryDialogueHandler"))  -- must exist, ModuleScript, returns a value

-- Keybind remotes
ensureRemote(remotes, "ActivateNode") -- you already have this
local function ensureRemoteFunction(folder, name)
	local rf = folder:FindFirstChild(name)
	if not rf then rf = Instance.new("RemoteFunction"); rf.Name = name; rf.Parent = folder end
	return rf
end
ensureRemoteFunction(remotes, "GetKeybinds")      -- client <-> server
ensureRemoteFunction(remotes, "SetKeybind")       -- client <-> server
ensureRemoteFunction(remotes, "GetUnlockedNodes") -- client <-> server
require(script.Parent:WaitForChild("KeybindHandler"))


