-- ServerScriptService/00_RemotesInit.server.lua
-- Idempotently creates RemoteEvents/RemoteFunctions before anything else runs.

local RS = game:GetService("ReplicatedStorage")

local rem = RS:FindFirstChild("RemoteEvents")
if not rem then
    rem = Instance.new("Folder")
    rem.Name = "RemoteEvents"
    rem.Parent = RS
end

local function ensureEvent(name)
    local ev = rem:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = rem
    end
    return ev
end

local function ensureFunc(name)
    local rf = rem:FindFirstChild(name)
    if not rf then
        rf = Instance.new("RemoteFunction")
        rf.Name = name
        rf.Parent = rem
    end
    return rf
end

-- Core gameplay events
ensureEvent("ActivateNode")
ensureEvent("UnlockNode")
ensureEvent("NodeActions")
ensureEvent("ConfirmSuccess")
ensureEvent("CooldownNotice")
ensureEvent("DodgeCharges")

-- Story/dialogue
ensureEvent("UnlockStory")
ensureEvent("BeginDialogue")
ensureEvent("ChooseOption")
ensureEvent("DialogueUpdate")

-- Horse client expects this (and maybe more later)
ensureEvent("Horse_Face")

-- Keybind RFs
ensureFunc("GetKeybinds")
ensureFunc("SetKeybind")
ensureFunc("GetUnlockedNodes")

-- Optional scaffolding folders used elsewhere
if not RS:FindFirstChild("StoryUnlockables") then
    local f = Instance.new("Folder")
    f.Name = "StoryUnlockables"
    f.Parent = RS
end
if not RS:FindFirstChild("Stories") then
    local f = Instance.new("Folder")
    f.Name = "Stories"
    f.Parent = RS
end

print("[00_RemotesInit] Remotes ready.")