local ServerStorage = game:GetService("ServerStorage")
local RS            = game:GetService("ReplicatedStorage")
local Debris        = game:GetService("Debris")

-- Optional: skinning helper from earlier. If you didn't make it yet, comment these 2 lines.
local RigMadLibs    = RS:FindFirstChild("RigMadLibs") and require(RS.RigMadLibs)
local Looks         = RS:FindFirstChild("EnemyLooks") and require(RS.EnemyLooks)

local NPC_PREFABS     = ServerStorage:WaitForChild("NPCs")
local ENEMY_PREFABS   = ServerStorage:WaitForChild("Enemies")

local NPC_ANCHORS     = workspace:FindFirstChild("NPCAnchors")
local ENEMY_LEASHES   = workspace:FindFirstChild("EnemyLeashes")

local function topCenterCF(p: BasePart)
	return p.CFrame * CFrame.new(0, p.Size.Y/2 + 0.1, 0)
end

local function pickLook(prefabName: string)
	if not Looks then return nil end
	local list = Looks[prefabName]
	if not (list and #list > 0) then return nil end
	return list[math.random(1, #list)]
end

local function pivotAndFace(rig: Model, cf: CFrame)
	-- Use PivotTo so HRP + full model follows
	if rig and rig.PrimaryPart then
		rig:PivotTo(cf)
	else
		-- fallback: try to set PrimaryPart
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp then rig.PrimaryPart = hrp end
		rig:PivotTo(cf)
	end
end

local function spawnFromFolder(folder: Instance, prefabName: string)
	return folder:FindFirstChild(prefabName) and folder[prefabName]:Clone() or nil
end

-- === NPCs (stationary) ===
local function spawnNPCAt(anchor: BasePart)
	local prefabName = anchor:GetAttribute("Prefab")
	if not prefabName then warn("NPC anchor missing Prefab:", anchor:GetFullName()) return end

	local rig = spawnFromFolder(NPC_PREFABS, prefabName)
	if not rig then warn("NPC prefab not found:", prefabName) return end

	rig.Name = prefabName
	rig.Parent = workspace
	pivotAndFace(rig, topCenterCF(anchor))

	-- Optional skin
	pcall(function()
		if RigMadLibs then RigMadLibs.applyUserLook(rig, 1) end -- demo; replace with your choice or use EnemyLooks
	end)

	-- Keep where we spawned it
	rig:SetAttribute("IsNPC", true)
	rig:SetAttribute("AnchorName", anchor.Name)

	-- Respawn behavior (usually false for NPCs)
	if anchor:GetAttribute("Respawn") then
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				local t = anchor:GetAttribute("RespawnTime") or 8
				task.delay(t, function()
					if anchor.Parent then spawnNPCAt(anchor) end
				end)
			end)
		end
	end

	return rig
end

-- === Enemies (leashed) ===
local function spawnEnemyAt(leash: BasePart)
	local prefabName = leash:GetAttribute("Prefab")
	if not prefabName then warn("Leash missing Prefab:", leash:GetFullName()) return end

	local rig = spawnFromFolder(ENEMY_PREFABS, prefabName)
	if not rig then warn("Enemy prefab not found:", prefabName) return end

	rig.Name = prefabName
	rig.Parent = workspace:FindFirstChild("Enemies") or workspace
	pivotAndFace(rig, topCenterCF(leash))

	-- Stamp leash attributes for the AI to use later
	rig:SetAttribute("LeashCenterX", leash.Position.X)
	rig:SetAttribute("LeashCenterY", leash.Position.Y)
	rig:SetAttribute("LeashCenterZ", leash.Position.Z)
	rig:SetAttribute("LeashRadius", leash:GetAttribute("LeashRadius") or 30)
	rig:SetAttribute("ArenaId", leash:GetAttribute("ArenaId") or "")

	-- Optional look randomizer
	pcall(function()
		if RigMadLibs then
			local look = pickLook(prefabName)
			if look then RigMadLibs.spawn(prefabName, rig.Parent, rig.PrimaryPart and rig.PrimaryPart.CFrame or rig:GetPivot(), look) end
			-- If you use the line above, delete `rig` first or modify RigMadLibs to apply look to an existing rig.
		end
	end)

	-- Respawn on death (typical for enemies)
	local shouldRespawn = leash:GetAttribute("Respawn")
	if shouldRespawn == nil then shouldRespawn = true end
	if shouldRespawn then
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				local t = leash:GetAttribute("RespawnTime") or 10
				task.delay(t, function()
					if leash.Parent then spawnEnemyAt(leash) end
				end)
			end)
		end
	end

	return rig
end

-- === Boot ===
if NPC_ANCHORS then
	for _, a in ipairs(NPC_ANCHORS:GetChildren()) do
		if a:IsA("BasePart") then
			local count = math.max(1, tonumber(a:GetAttribute("Count") or 1))
			for i = 1, count do spawnNPCAt(a) end
		end
	end
end

if ENEMY_LEASHES then
	for _, l in ipairs(ENEMY_LEASHES:GetChildren()) do
		if l:IsA("BasePart") then
			local count = math.max(1, tonumber(l:GetAttribute("Count") or 1))
			for i = 1, count do
				-- slight radial offset for multiple spawns at one leash
				local cf = topCenterCF(l) * CFrame.new(math.sin(i)*2, 0, math.cos(i)*2)
				local rig = spawnEnemyAt(l)
				if rig then pivotAndFace(rig, cf) end
			end
		end
	end
end
