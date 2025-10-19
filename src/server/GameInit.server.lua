-- src/server/GameInit.server.lua
-- Creates remotes, wires player load/unload, boots story + keybind systems.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sss               = script.Parent
local PlayerDataService = require(sss:WaitForChild("PlayerDataService"))
local NodeManager       = require(ReplicatedStorage:WaitForChild("NodeManager"))

-- Remote bootstrap -----------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
remotes.Name = "RemoteEvents"
remotes.Parent = ReplicatedStorage

local function ensureRemote(name)
  local ev = remotes:FindFirstChild(name)
  if not ev then ev = Instance.new("RemoteEvent"); ev.Name = name; ev.Parent = remotes end
  return ev
end

local function ensureRemoteFunction(name)
  local rf = remotes:FindFirstChild(name)
  if not rf then rf = Instance.new("RemoteFunction"); rf.Name = name; rf.Parent = remotes end
  return rf
end

-- Events used elsewhere
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

-- Keybind RemoteFunctions
ensureRemoteFunction("GetKeybinds")
ensureRemoteFunction("SetKeybind")
ensureRemoteFunction("GetUnlockedNodes")

-- Story scaffolding folders
local storyAllow = ReplicatedStorage:FindFirstChild("StoryUnlockables") or Instance.new("Folder", ReplicatedStorage)
storyAllow.Name = "StoryUnlockables"
local stories = ReplicatedStorage:FindFirstChild("Stories") or Instance.new("Folder", ReplicatedStorage)
stories.Name = "Stories"

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

-- Boot story/keybind systems -------------------------------------------------
require(sss:WaitForChild("StoryDataService"))
require(sss:WaitForChild("StoryUnlockHandler"))
require(sss:WaitForChild("StoryDialogueHandler"))
require(sss:WaitForChild("StoryUnlockables")) -- or your StoryList
require(sss:WaitForChild("KeybindHandler"))
