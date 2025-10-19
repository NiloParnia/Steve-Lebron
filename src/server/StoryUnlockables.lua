-- StoryUnlockables.lua
-- Master allow-list for story IDs; mirrors to RS/StoryUnlockables as StringValues

local RS = game:GetService("ReplicatedStorage")

local StoryAllow = {
	"Hotpants_Start",
	"Horse_Keeper",
	"Johnny_Joestar_Start",
	-- add more storyIds here...
}

local folder = RS:FindFirstChild("StoryUnlockables")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "StoryUnlockables"
	folder.Parent = RS
end

for _, child in ipairs(folder:GetChildren()) do child:Destroy() end
for _, id in ipairs(StoryAllow) do
	local sv = Instance.new("StringValue")
	sv.Name = id
	sv.Value = id
	sv.Parent = folder
end

return StoryAllow
