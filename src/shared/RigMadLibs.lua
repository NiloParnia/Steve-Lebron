-- ReplicatedStorage/RigMadLibs.lua
local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris        = game:GetService("Debris")

local M = {}

local function getHumanoid(rig)
	return rig and rig:FindFirstChildOfClass("Humanoid")
end

local function ensureEnemiesFolder()
	local f = ServerStorage:FindFirstChild("Enemies")
	assert(f, "Put your enemy prefabs in ServerStorage/Enemies")
	return f
end

local function asCSV(list)
	if not list or #list == 0 then return "" end
	local out = {}
	for _, id in ipairs(list) do table.insert(out, tostring(id)) end
	return table.concat(out, ",")
end

-- === SKINNING HELPERS ===
function M.applyUserLook(rig: Model, userId: number)
	local hum = getHumanoid(rig); if not hum then return false end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
	if ok and desc then hum:ApplyDescription(desc); return true end
	return false
end

function M.applyOutfit(rig: Model, outfitId: number)
	local hum = getHumanoid(rig); if not hum then return false end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromOutfitId, Players, outfitId)
	if ok and desc then hum:ApplyDescription(desc); return true end
	return false
end

-- assets = { shirt=, pants=, face=, hats={}, hair={}, back={}, faceAcc={}, neck={}, front={}, shoulder={}, waist={} }
function M.applyAssets(rig: Model, assets: table)
	local hum = getHumanoid(rig); if not hum then return false end
	local desc = Instance.new("HumanoidDescription")

	-- Classic clothing / face (optional)
	if assets.shirt then desc.Shirt = assets.shirt end
	if assets.pants then desc.Pants = assets.pants end
	if assets.face  then desc.Face  = assets.face end

	-- Accessories (comma-separated strings of asset IDs)
	if assets.hats     then desc.HatAccessory       = asCSV(assets.hats) end
	if assets.hair     then desc.HairAccessory      = asCSV(assets.hair) end
	if assets.back     then desc.BackAccessory      = asCSV(assets.back) end
	if assets.faceAcc  then desc.FaceAccessory      = asCSV(assets.faceAcc) end
	if assets.neck     then desc.NeckAccessory      = asCSV(assets.neck) end
	if assets.front    then desc.FrontAccessory     = asCSV(assets.front) end
	if assets.shoulder then desc.ShoulderAccessory  = asCSV(assets.shoulder) end
	if assets.waist    then desc.WaistAccessory     = asCSV(assets.waist) end

	hum:ApplyDescription(desc)
	return true
end

-- === SPAWN/PREVIEW ===
-- look = { userId = n } OR { outfitId = n } OR { assets = {...} } OR nil
function M.spawn(prefabName: string, parent: Instance?, cf: CFrame?, look: table?)
	local enemies = ensureEnemiesFolder()
	local template = enemies:FindFirstChild(prefabName)
	assert(template, ("Prefab not found: %s in ServerStorage/Enemies"):format(prefabName))

	local rig = template:Clone()
	if cf then rig:PivotTo(cf) end
	rig.Parent = parent or workspace

	if look then
		if look.userId then M.applyUserLook(rig, look.userId)
		elseif look.outfitId then M.applyOutfit(rig, look.outfitId)
		elseif look.assets then M.applyAssets(rig, look.assets)
		end
	end
	return rig
end

-- opts = { anchor=true, autoclean=seconds, nameSuffix="Preview" }
function M.preview(prefabName: string, cf: CFrame?, look: table?, opts: table?)
	opts = opts or {}
	local rig = M.spawn(prefabName, workspace, cf or CFrame.new(0,5,0), look)
	rig.Name = (opts.nameSuffix or "Preview") .. "_" .. prefabName

	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if hrp and (opts.anchor ~= false) then hrp.Anchored = true end

	if tonumber(opts.autoclean) then Debris:AddItem(rig, opts.autoclean) end
	return rig
end

function M.clearPreviews(prefix: string?)
	prefix = prefix or "Preview_"
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(1, #prefix) == prefix then
			m:Destroy()
		end
	end
end

return M
