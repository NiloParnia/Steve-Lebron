-- Unlockables.lua (ServerScriptService)
-- Master list of all unlockable nodes beyond the defaults.
-- Also mirrors them into ReplicatedStorage/Unlockables as StringValues.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unlockables = {
	"Revolver",
	"SummonHorse",
	"Gallop", 
	-- add future unlockable moves here...
}

-- Mirror to RS/Unlockables for clients/NodeManager/PlayerDataService
local folder = ReplicatedStorage:FindFirstChild("Unlockables")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Unlockables"
	folder.Parent = ReplicatedStorage
end
for _, child in ipairs(folder:GetChildren()) do child:Destroy() end
for _, name in ipairs(Unlockables) do
	local sv = Instance.new("StringValue")
	sv.Name = name
	sv.Value = name
	sv.Parent = folder
end

return Unlockables