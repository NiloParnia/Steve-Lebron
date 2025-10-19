local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("RemoteEvents")
local BeginDlg = Remotes:WaitForChild("BeginDialogue")

local function wire(model)
	local prompt = model:FindFirstChildOfClass("ProximityPrompt")
	print("[NPC] wire?", model:GetFullName(), "prompt=", prompt)
	if not prompt then
		warn("[NPC] No ProximityPrompt on", model:GetFullName())
		return
	end
	local storyId = model:GetAttribute("storyId")
	local startNode = model:GetAttribute("startNode")
	print("[NPC] attrs storyId=", storyId, "startNode=", startNode)

	if type(storyId) ~= "string" or storyId == "" then
		warn("[NPC] Missing storyId on", model:GetFullName()); return
	end

	prompt.Enabled = true
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 16
	prompt.HoldDuration = 0

	prompt.Triggered:Connect(function(player)
		print("[NPC] Triggered by", player.Name, "→ FireClient BeginDialogue")
		BeginDlg:FireClient(player, storyId, startNode)
	end)
end

for _, m in ipairs(CollectionService:GetTagged("DialogueNPC")) do wire(m) end
CollectionService:GetInstanceAddedSignal("DialogueNPC"):Connect(wire)
print("[NPC] Trigger script ready; tagged count:", #CollectionService:GetTagged("DialogueNPC"))
print()