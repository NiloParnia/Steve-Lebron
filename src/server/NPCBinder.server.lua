local RS        = game:GetService("ReplicatedStorage")
local RigKit    = require(RS:WaitForChild("RigMadLibs"))   -- from earlier
local Looks     = require(RS:WaitForChild("EnemyLooks"))

local ROOT = workspace:FindFirstChild("NPCs") or workspace

local function applyLook(model: Model)
	if not model:FindFirstChildOfClass("Humanoid") then return end
	if not model:GetAttribute("IsNPC") then return end
	if model:GetAttribute("Skinned") then return end  -- idempotent

	-- Priority: LookKey > storyId > Name
	local key = model:GetAttribute("LookKey") or model:GetAttribute("storyId") or model.Name
	local options = Looks[key]
	if not options or #options == 0 then return end

	local entry = options[1]  -- or pick by index/random if you want
	if entry.userId   then RigKit.applyUserLook(model, entry.userId)
	elseif entry.outfitId then RigKit.applyOutfit(model, entry.outfitId)
	elseif entry.assets   then RigKit.applyAssets(model, entry.assets) end

	model:SetAttribute("Skinned", true)
end

-- Initial pass + handle NPCs added later
for _, m in ipairs(ROOT:GetDescendants()) do
	if m:IsA("Model") then applyLook(m) end
end

ROOT.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") then applyLook(inst) end
end)
